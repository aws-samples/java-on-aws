# Design Document: JVM Analysis Service Java 25 Modernization

## Overview

This design modernizes the `jvm-analysis-service` from Java 21/Spring Boot 3.x to Java 25/Spring Boot 4, replacing raw AWS SDK Bedrock calls with Spring AI. The architecture follows patterns established in `unicorn-store-spring` for consistency across the Java 25 workshop applications.

### Key Changes from Original Implementation

| Aspect | Original | Modernized |
|--------|----------|------------|
| Java Version | 21 | 25 |
| Spring Boot | 3.5.8 | 4.0.0 |
| AI Integration | Raw BedrockRuntimeClient | Spring AI ChatClient |
| DTOs | Mutable POJOs | Java Records |
| Configuration | .properties | .yaml |
| Testing | Basic JUnit | Testcontainers 2.0.3 + jqwik |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    JVM Analysis Service                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │ JvmAnalysis      │───▶│ JvmAnalysis      │                   │
│  │ Controller       │    │ Service          │                   │
│  │ (REST API)       │    │ (Orchestration)  │                   │
│  └──────────────────┘    └────────┬─────────┘                   │
│                                   │                              │
│         ┌─────────────────────────┼─────────────────────────┐   │
│         │                         │                         │   │
│         ▼                         ▼                         ▼   │
│  ┌──────────────┐    ┌──────────────────┐    ┌─────────────┐   │
│  │ S3Connector  │    │ AiAnalyzer       │    │ ThreadDump  │   │
│  │ (S3 ops)     │    │ (Spring AI)      │    │ Client      │   │
│  └──────┬───────┘    └────────┬─────────┘    └──────┬──────┘   │
│         │                     │                      │          │
└─────────┼─────────────────────┼──────────────────────┼──────────┘
          │                     │                      │
          ▼                     ▼                      ▼
    ┌──────────┐         ┌──────────┐          ┌──────────┐
    │   S3     │         │ Bedrock  │          │ Target   │
    │          │         │ (Claude) │          │ Pod      │
    └──────────┘         └──────────┘          └──────────┘
```

## Components and Interfaces

### 1. Data Models (Java Records)

```java
// Alert webhook request - immutable record
public record AlertWebhookRequest(List<Alert> alerts) {
    public record Alert(Labels labels) {}
    public record Labels(String pod, String instance) {
        public String podIp() {
            return instance != null ? instance.split(":")[0] : null;
        }
    }
}

// Analysis result
public record AnalysisResult(String message, int count) {}

// Internal processing result
public record ProcessingResult(
    String podName,
    String threadDump,
    String profilingData,
    String analysis
) {}
```

### 2. JvmAnalysisController

REST controller handling webhook requests with validation.

```java
@RestController
public class JvmAnalysisController {

    private final JvmAnalysisService service;

    // Flexible Constructor Bodies (JEP 513) - validation before super/this
    public JvmAnalysisController(JvmAnalysisService service) {
        Objects.requireNonNull(service, "service must not be null");
        this.service = service;
    }

    @PostMapping("/webhook")
    public AnalysisResult handleWebhook(@RequestBody AlertWebhookRequest request) {
        if (request.alerts() == null || request.alerts().isEmpty()) {
            return new AnalysisResult("No alerts to process", 0);
        }

        var validAlerts = request.alerts().stream()
            .filter(this::isValidAlert)
            .toList();

        return service.processAlerts(validAlerts);
    }

    private boolean isValidAlert(AlertWebhookRequest.Alert alert) {
        // Pattern matching with record patterns
        return alert instanceof AlertWebhookRequest.Alert(var labels)
            && labels != null
            && labels.pod() != null && !labels.pod().isBlank()
            && labels.podIp() != null && !labels.podIp().isBlank();
    }
}
```

### 3. JvmAnalysisService

Orchestrates the analysis workflow.

```java
@Service
public class JvmAnalysisService {

    private final S3Connector s3Connector;
    private final AiAnalyzer aiAnalyzer;
    private final RestClient restClient;

    @Value("${jvm-analysis.thread-dump.url-template}")
    private String threadDumpUrlTemplate;

    public AnalysisResult processAlerts(List<AlertWebhookRequest.Alert> alerts) {
        int count = 0;
        for (var alert : alerts) {
            try {
                processAlert(alert);
                count++;
            } catch (Exception _) {
                // Unnamed variable (JEP 456) - exception details logged elsewhere
            }
        }
        return new AnalysisResult("Processed alerts", count);
    }

    private void processAlert(AlertWebhookRequest.Alert alert) {
        var labels = alert.labels();
        var podName = labels.pod();
        var podIp = labels.podIp();

        var threadDump = getThreadDump(podIp);
        var profilingData = s3Connector.getLatestProfilingData(podName);
        var analysis = aiAnalyzer.analyze(threadDump, profilingData);

        s3Connector.storeResults(podName, threadDump, profilingData, analysis);
    }
}
```

### 4. AiAnalyzer (Spring AI)

Replaces raw BedrockRuntimeClient with Spring AI ChatClient.

```java
@Component
public class AiAnalyzer {

    private final ChatClient chatClient;

    public AiAnalyzer(ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClientBuilder.build();
    }

    public String analyze(String threadDump, String profilingData) {
        var prompt = buildPrompt(threadDump, profilingData);

        try {
            return chatClient.prompt()
                .system(SYSTEM_PROMPT)
                .user(prompt)
                .call()
                .content();
        } catch (Exception e) {
            return buildFallbackReport(e, threadDump, profilingData);
        }
    }

    private static final String SYSTEM_PROMPT = """
        You are an expert in Java performance analysis with extensive experience
        diagnosing production issues. Analyze thread dumps and profiling data to
        identify performance bottlenecks and provide actionable recommendations.
        """;

    private String buildPrompt(String threadDump, String profilingData) {
        return """
            Analyze this Java performance data and provide a focused report:

            ## Health Status
            Rate: Healthy/Degraded/Critical with brief explanation

            ## Thread Analysis
            - Total threads and state distribution
            - Key patterns and bottlenecks

            ## Top Issues (max 3)
            - Problem, Root Cause, Impact, Fix

            ## Performance Hotspots
            From flamegraph: CPU consumers, memory patterns, I/O bottlenecks

            ## Recommendations
            Immediate (< 1 day) and Short-term (< 1 week)

            **Thread Dump:**
            %s

            **Flamegraph Data:**
            %s
            """.formatted(threadDump, profilingData);
    }
}
```

### 5. S3Connector

S3 operations with improved error handling.

```java
@Component
public class S3Connector {

    private final S3Client s3Client;

    @Value("${jvm-analysis.s3.bucket}")
    private String bucket;

    @Value("${jvm-analysis.s3.prefix.analysis:analysis/}")
    private String analysisPrefix;

    @Value("${jvm-analysis.s3.prefix.profiling:profiling/}")
    private String profilingPrefix;

    public S3Connector(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    public String getLatestProfilingData(String podName) {
        var prefix = profilingPrefix + podName + "/profile-" + currentDate();

        var response = s3Client.listObjectsV2(req -> req
            .bucket(bucket)
            .prefix(prefix));

        // Sequenced Collections - getLast() for most recent
        return response.contents().stream()
            .filter(obj -> obj.key().endsWith(".html"))
            .max(Comparator.comparing(S3Object::lastModified))
            .map(obj -> fetchObject(obj.key()))
            .orElse("No profiling data available");
    }

    public void storeResults(String podName, String threadDump,
                            String profilingData, String analysis) {
        var timestamp = currentTimestamp();

        putObject(analysisPrefix + timestamp + "_threaddump_" + podName + ".json", threadDump);
        putObject(analysisPrefix + timestamp + "_profiling_" + podName + ".html", profilingData);
        putObject(analysisPrefix + timestamp + "_analysis_" + podName + ".md", analysis);
    }
}
```

## Data Models

### Request/Response Flow

```
POST /webhook
    │
    ▼
AlertWebhookRequest (Record)
    ├── alerts: List<Alert>
    │       └── Alert (Record)
    │           └── labels: Labels (Record)
    │               ├── pod: String
    │               └── instance: String (contains IP:port)
    │
    ▼
AnalysisResult (Record)
    ├── message: String
    └── count: int
```

### S3 Storage Structure

```
{bucket}/
├── profiling/
│   └── {pod-name}/
│       └── profile-{date}/
│           └── {timestamp}.html
└── analysis/
    ├── {timestamp}_threaddump_{pod-name}.json
    ├── {timestamp}_profiling_{pod-name}.html
    └── {timestamp}_analysis_{pod-name}.md
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Alert Validation Consistency

*For any* alert, it is processed if and only if it has non-blank pod label AND non-blank podIp (derived from instance label).

**Validates: Requirements 4.2, 4.3**

### Property 2: AI Analysis Contains Input Context

*For any* thread dump and profiling data inputs, the prompt sent to the AI model SHALL contain both the thread dump content and the profiling data content.

**Validates: Requirements 2.3**

### Property 3: AI Fallback on Error

*For any* exception thrown during AI analysis, the analyzer SHALL return a non-null fallback report containing error information.

**Validates: Requirements 2.4**

### Property 4: Webhook Response Structure

*For any* webhook request (valid or invalid), the response SHALL contain both a "message" field (non-null String) and a "count" field (non-negative integer).

**Validates: Requirements 4.5**

### Property 5: S3 Storage Completeness

*For any* successful analysis, the S3Connector SHALL store exactly three files: thread dump (.json), profiling data (.html), and analysis report (.md).

**Validates: Requirements 6.2**

## Error Handling

### Retry Strategy (Thread Dump Retrieval)

```yaml
resilience4j:
  retry:
    instances:
      threadDump:
        max-attempts: 3
        wait-duration: 2s
        exponential-backoff-multiplier: 2
        retry-exceptions:
          - java.net.ConnectException
          - java.net.SocketTimeoutException
```

### Fallback Behaviors

| Component | Failure | Fallback |
|-----------|---------|----------|
| Thread Dump | HTTP error | Error message with details |
| S3 Read | Not found | "No profiling data available" |
| AI Analysis | API error | Fallback report with inputs summary |
| S3 Write | Error | Log and continue (non-blocking) |

## Testing Strategy

### Unit Tests

- Alert validation logic (valid/invalid combinations)
- Record serialization/deserialization
- Prompt building with various inputs
- Fallback report generation

### Property-Based Tests (jqwik)

- Alert validation: random alerts with various label combinations
- Response structure: all responses have required fields
- AI prompt: always contains both inputs

### Integration Tests (Testcontainers)

- S3 operations with LocalStack
- Full webhook flow with mocked AI

### Test Infrastructure

```java
public class TestInfrastructureInitializer implements BeforeAllCallback {

    private static LocalStackContainer localstack;

    @Override
    public void beforeAll(ExtensionContext context) {
        try {
            DockerClientFactory.instance().client();
            initializeLocalStack();
        } catch (Exception _) {
            // Unnamed variable - Docker unavailable, skip S3 tests
            initializeMockFallback();
        }
    }

    private void initializeLocalStack() {
        localstack = new LocalStackContainer(DockerImageName.parse("localstack/localstack:3.0"))
            .withServices("s3")
            .withReuse(true);
        localstack.start();

        System.setProperty("spring.cloud.aws.s3.endpoint",
            localstack.getEndpoint().toString());
        System.setProperty("spring.cloud.aws.credentials.access-key", "test");
        System.setProperty("spring.cloud.aws.credentials.secret-key", "test");
        System.setProperty("spring.cloud.aws.region.static", "us-east-1");
    }
}
```

## Configuration

### application.yaml

```yaml
spring:
  application:
    name: jvm-analysis-service

  threads:
    virtual:
      enabled: true

  jmx:
    enabled: false

  ai:
    bedrock:
      anthropic:
        chat:
          enabled: true
          model: anthropic.claude-sonnet-4-20250514-v1:0
          max-tokens: 10000

jvm-analysis:
  thread-dump:
    url-template: http://{podIp}:8080/actuator/threaddump
  s3:
    bucket: ${AWS_S3_BUCKET:jvm-analysis-bucket}
    prefix:
      analysis: analysis/
      profiling: profiling/

server:
  shutdown: graceful

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true

resilience4j:
  retry:
    instances:
      threadDump:
        max-attempts: 3
        wait-duration: 2s
        exponential-backoff-multiplier: 2
```

## Documentation Guidelines

This section defines the commenting and documentation strategy for Java 25 workshop applications. The goal is minimal, purposeful documentation that lets code be self-documenting.

### Main Source Files

- **No class-level Javadoc** - annotations speak for themselves
- **No method-level Javadoc** - method names and signatures should be self-explanatory
- **JEP feature comments only** - single-line format: `// Java 25 Feature Name (JEP XXX)`
- **Brief inline comments** - only for non-obvious logic, keep concise

Example:
```java
@Service
public class AnalyzerService {

    public String analyze(String threadDump, String profilingData) {
        // Java 22 unnamed variable (JEP 456)
        try {
            return chatClient.prompt().call().content();
        } catch (Exception _) {
            return buildFallbackReport();
        }
    }
}
```

### Test Classes

- **Single-line class comment** - describes what the class tests
- **Section separators** - use `// --- Section Name ---` to group related tests
- **No method-level comments** - test method names should be descriptive

Example:
```java
// Property tests for alert validation logic
class AlertValidationPropertyTest {

    // --- Valid Alert Tests ---

    @Property
    void validAlertIsAccepted() { ... }

    // --- Providers ---

    @Provide
    Arbitrary<String> validPodNames() { ... }
}
```

### What NOT to Document

- Constructor parameter validation (code is obvious)
- Standard Spring annotations (@Service, @RestController, etc.)
- Getter/setter methods
- Simple delegation methods
- Exception handling unless using JEP features

## Dependencies

### pom.xml Key Dependencies

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.0.0</version>
</parent>

<properties>
    <java.version>25</java.version>
    <spring-ai.version>1.0.0</spring-ai.version>
    <testcontainers.version>2.0.3</testcontainers.version>
</properties>

<dependencies>
    <!-- Spring Boot -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>

    <!-- Spring AI for Bedrock -->
    <dependency>
        <groupId>org.springframework.ai</groupId>
        <artifactId>spring-ai-bedrock-ai-spring-boot-starter</artifactId>
    </dependency>

    <!-- AWS SDK -->
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>s3</artifactId>
    </dependency>

    <!-- Resilience -->
    <dependency>
        <groupId>io.github.resilience4j</groupId>
        <artifactId>resilience4j-spring-boot3</artifactId>
    </dependency>

    <!-- Testing -->
    <dependency>
        <groupId>net.jqwik</groupId>
        <artifactId>jqwik</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers-localstack</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```
