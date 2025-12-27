# JVM AI Analyzer - Java 25 + Spring Boot 4 + Spring AI

An AI-powered JVM performance analysis service that processes Prometheus alerts, collects thread dumps and flamegraph data, and generates actionable recommendations using Amazon Bedrock.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Prometheus AlertManager                    │
│                    (webhook trigger)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  AnalyzerController                                         │
│  - POST /webhook endpoint                                   │
│  - Alert validation (pod + podIp required)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  AnalyzerService                                            │
│  - Orchestrates analysis workflow                           │
│  - Fetches thread dump from target pod                      │
│  - Coordinates S3 and AI operations                         │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  S3Repository   │  │  AiAnalysis     │  │  Target Pod     │
│  - Get profiling│  │  Service        │  │  /actuator/     │
│  - Store results│  │  - Spring AI    │  │  threaddump     │
└────────┬────────┘  │  - Claude       │  └─────────────────┘
         │           └────────┬────────┘
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│      S3         │  │    Bedrock      │
│  profiling/     │  │    (Claude)     │
│  analysis/      │  │                 │
└─────────────────┘  └─────────────────┘
```

## Project Structure

```
src/main/java/com/unicorn/jvm/
├── JvmAiAnalyzerApplication.java  # Spring Boot entry point
├── AnalyzerController.java        # REST webhook endpoint
├── AnalyzerService.java           # Analysis orchestration
├── AiAnalysisService.java         # Spring AI + Bedrock integration
├── S3Repository.java              # S3 operations (read/write)
├── AlertWebhookRequest.java       # Request record (nested Alert, Labels)
└── AnalysisResult.java            # Response record
```

## Modern Java Features

| Feature | JEP | Location | Description |
|---------|-----|----------|-------------|
| Flexible Constructor Bodies | [513](https://openjdk.org/jeps/513) | `AnalyzerController` | Validation before field assignment |
| Unnamed Variables | [456](https://openjdk.org/jeps/456) | catch blocks | `catch (Exception _)` when variable unused |
| Record Patterns | [440](https://openjdk.org/jeps/440) | `AnalyzerController.isValidAlert()` | Destructuring in pattern matching |
| Text Blocks | 378 | `AiAnalysisService` | Multi-line AI prompts |
| Virtual Threads | 444 | `application.yaml` | `spring.threads.virtual.enabled: true` |
| Records | 395 | `AlertWebhookRequest`, `AnalysisResult` | Immutable data carriers |

## Data Flow

```
POST /webhook
    │
    ▼
AlertWebhookRequest
├── alerts: List<Alert>
│       └── Alert
│           └── Labels
│               ├── pod: "unicorn-store-xyz"
│               └── instance: "10.0.1.5:8080"
    │
    ▼ (for each valid alert)
    │
┌───┴───────────────────────────────────────┐
│ 1. Fetch thread dump from pod             │
│    GET http://{podIp}:8080/actuator/      │
│        threaddump                         │
│                                           │
│ 2. Get latest flamegraph from S3          │
│    s3://{bucket}/profiling/{pod}/         │
│        profile-{date}/*.html              │
│                                           │
│ 3. AI analysis via Spring AI + Bedrock    │
│    - Health status assessment             │
│    - Thread analysis                      │
│    - Performance hotspots                 │
│    - Recommendations                      │
│                                           │
│ 4. Store results to S3                    │
│    s3://{bucket}/analysis/                │
│    ├── {ts}_threaddump_{pod}.json         │
│    ├── {ts}_profiling_{pod}.html          │
│    └── {ts}_analysis_{pod}.md             │
└───────────────────────────────────────────┘
    │
    ▼
AnalysisResult
├── message: "Processed alerts"
└── count: 1
```

## Testing

```bash
# Run all tests (27 total)
mvn test

# Tests use Testcontainers 2.0 with LocalStack for S3
```

**Test Infrastructure:**
- `@TestInfrastructure` - unified annotation for integration tests
- LocalStack for S3 operations
- Mocked ChatClient for AI tests
- Property-based tests with jqwik for validation logic

## Building

```bash
mvn package           # Standard JAR
mvn package -Pnative  # Native image (GraalVM)
```

## Configuration

```yaml
jvm-ai-analyzer:
  thread-dump:
    url-template: http://{podIp}:8080/actuator/threaddump
  s3:
    bucket: ${AWS_S3_BUCKET:jvm-analysis-bucket}
    prefix:
      analysis: analysis/
      profiling: profiling/

spring:
  ai:
    bedrock:
      anthropic:
        chat:
          model: anthropic.claude-sonnet-4-20250514-v1:0
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/webhook` | Process Prometheus alerts |
| GET | `/actuator/health` | Health check |
| GET | `/actuator/prometheus` | Metrics |
