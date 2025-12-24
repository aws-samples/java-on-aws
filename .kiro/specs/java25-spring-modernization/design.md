# Design Document: Java 25 + Spring Boot 4 Modernization

## Overview

This design document describes the architecture and implementation of the `apps/java25/unicorn-store-spring` application as a **showcase workshop application** demonstrating Java 25, Spring Framework 7, and Spring Boot 4 best practices.

**Location:** `apps/java25/unicorn-store-spring/`
**Dockerfiles:** `apps/java25/dockerfiles/`

The application is a RESTful CRUD service for managing unicorn entities, integrated with AWS EventBridge for event publishing. It serves as the centerpiece of an AWS workshop demonstrating:
- Java deployment options (EKS, ECS)
- Container optimizations (multi-stage builds, jlink, native images, CDS, CRaC, AOT)
- Modern Java 25 language features
- Spring Boot 4 / Spring Framework 7 patterns

### Design Principles

1. **Showcase, Not Showoff**: Every Java 25 feature used must provide genuine value to this specific application
2. **Production-Ready**: Code quality that developers would be proud to reference
3. **Container-Optimized**: Architecture decisions that support various container optimization techniques
4. **Testable**: Clean test architecture that demonstrates proper Spring Boot testing patterns

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        HTTP Clients                              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    UnicornController                             │
│  - REST endpoints (CRUD)                                         │
│  - Request validation                                            │
│  - Response mapping                                              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     UnicornService                               │
│  - Business logic                                                │
│  - Pattern matching validation                                   │
│  - Transaction management                                        │
│  - Scoped Value access for request context                       │
└─────────────────────────────────────────────────────────────────┘
                    │                       │
                    ▼                       ▼
┌───────────────────────────┐   ┌─────────────────────────────────┐
│    UnicornRepository      │   │      UnicornPublisher           │
│  - JPA/Hibernate          │   │  - EventBridge integration      │
│  - PostgreSQL             │   │  - Async event publishing       │
└───────────────────────────┘   └─────────────────────────────────┘
                    │                       │
                    ▼                       ▼
┌───────────────────────────┐   ┌─────────────────────────────────┐
│      PostgreSQL           │   │      AWS EventBridge            │
└───────────────────────────┘   └─────────────────────────────────┘
```

### Request Flow with Scoped Values

```
HTTP Request
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│  RequestContextFilter                                            │
│  - Generate UUID request ID                                      │
│  - Bind to ScopedValue.runWhere(REQUEST_ID, uuid, ...)          │
└─────────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Controller → Service → Repository                               │
│  - Access RequestContext.REQUEST_ID.get() anywhere               │
│  - No parameter passing needed                                   │
│  - Automatic cleanup when request completes                      │
└─────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. Request Context (Scoped Values - JEP 506)

**Why Scoped Values?**
- ThreadLocal requires explicit cleanup and can leak memory
- Scoped Values are immutable and automatically cleaned up
- Better performance with Virtual Threads (no synchronization overhead)
- Demonstrates modern Java 25 context propagation

```java
/**
 * Request context using Java 25 Scoped Values (JEP 506).
 *
 * Scoped Values provide a modern alternative to ThreadLocal for sharing
 * immutable data within a thread and its child threads. Benefits:
 * - Automatic cleanup when scope exits (no memory leaks)
 * - Immutable by design (thread-safe)
 * - Optimized for Virtual Threads (no synchronization overhead)
 * - Clear lifetime boundaries
 */
public final class RequestContext {

    /**
     * The current request's unique identifier.
     * Bound at the start of each HTTP request and accessible
     * throughout the request processing chain.
     */
    public static final ScopedValue<String> REQUEST_ID = ScopedValue.newInstance();

    private RequestContext() {
        // Utility class - prevent instantiation
    }
}
```

**Filter Implementation:**

```java
/**
 * Filter that establishes request context using Scoped Values.
 *
 * This demonstrates the Java 25 pattern for request-scoped data:
 * - Generate unique request ID
 * - Bind to ScopedValue for the duration of the request
 * - Automatic cleanup when request completes
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestContextFilter implements Filter {

    private static final Logger logger = LoggerFactory.getLogger(RequestContextFilter.class);

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) throws IOException, ServletException {
        String requestId = UUID.randomUUID().toString();

        // Java 25 Scoped Values - bind request ID for entire request scope
        ScopedValue.runWhere(RequestContext.REQUEST_ID, requestId, () -> {
            try {
                logger.debug("Request started: {}", requestId);
                chain.doFilter(request, response);
            } catch (IOException | ServletException e) {
                throw new RuntimeException(e);
            } finally {
                logger.debug("Request completed: {}", requestId);
            }
        });
    }
}
```

### 2. Unicorn Model (Flexible Constructor Bodies - JEP 513)

**Why Flexible Constructor Bodies?**
- Validation belongs in the constructor, not scattered in service layer
- JEP 513 allows validation BEFORE field assignment
- Fail-fast: invalid objects can never be created
- Cleaner code: single point of validation

```java
/**
 * Unicorn entity demonstrating Java 25 Flexible Constructor Bodies (JEP 513).
 *
 * Flexible Constructor Bodies allow statements before the implicit super() call,
 * enabling validation before any field assignment. This ensures:
 * - Invalid objects can never be created
 * - Validation logic is centralized in the constructor
 * - Fail-fast behavior for invalid input
 */
@Entity(name = "unicorns")
public class Unicorn {

    @Id
    @JsonProperty("id")
    private String id;

    @JsonProperty("name")
    private String name;

    @JsonProperty("age")
    private String age;

    @JsonProperty("size")
    private String size;

    @JsonProperty("type")
    private String type;

    /**
     * JPA requires a no-arg constructor.
     */
    public Unicorn() {
    }

    /**
     * Creates a new Unicorn with validation using Flexible Constructor Bodies (JEP 513).
     *
     * The validation executes BEFORE the implicit super() call, ensuring
     * that invalid objects can never be partially constructed.
     *
     * @param name the unicorn's name (required, non-blank)
     * @param age the unicorn's age
     * @param size the unicorn's size
     * @param type the unicorn's type (required, non-blank)
     * @throws IllegalArgumentException if name or type is null/blank
     */
    public Unicorn(String name, String age, String size, String type) {
        // Java 25 Flexible Constructor Bodies (JEP 513)
        // Validation BEFORE implicit super() call
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Unicorn name is required and cannot be blank");
        }
        if (type == null || type.isBlank()) {
            throw new IllegalArgumentException("Unicorn type is required and cannot be blank");
        }
        // Now safe to assign fields
        this.name = name;
        this.age = age;
        this.size = size;
        this.type = type;
    }

    /**
     * Creates a copy with a new ID (immutable pattern).
     */
    public Unicorn withId(String newId) {
        var unicorn = new Unicorn(name, age, size, type);
        unicorn.id = newId;
        return unicorn;
    }

    // Standard JavaBean accessors (no duplicate record-style accessors)
    public String getId() { return id; }
    public String getName() { return name; }
    public String getAge() { return age; }
    public String getSize() { return size; }
    public String getType() { return type; }

    public void setId(String id) { this.id = id; }
    public void setName(String name) { this.name = name; }
    public void setAge(String age) { this.age = age; }
    public void setSize(String size) { this.size = size; }
    public void setType(String type) { this.type = type; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Unicorn unicorn)) return false;
        return id != null && id.equals(unicorn.id);
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
```

### 3. Service Layer (Pattern Matching Validation)

**Why Pattern Matching?**
- Already present in codebase - demonstrates real-world usage
- Cleaner than if-else chains for type-based logic
- Exhaustive checking by compiler
- Guarded patterns (`when` clause) for complex conditions

```java
/**
 * Service demonstrating Pattern Matching with switch expressions.
 *
 * Pattern matching provides:
 * - Exhaustive type checking by compiler
 * - Cleaner syntax than if-else chains
 * - Guarded patterns for complex conditions
 * - Request context access via Scoped Values
 */
@Service
public class UnicornService {

    private static final Logger logger = LoggerFactory.getLogger(UnicornService.class);

    @Transactional
    public Unicorn createUnicorn(Unicorn unicorn) {
        // Access request ID from Scoped Value (no parameter passing needed)
        String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
        logger.debug("[{}] Creating unicorn: {}", requestId, unicorn.getName());

        var unicornWithId = unicorn.getId() == null
            ? unicorn.withId(UUID.randomUUID().toString())
            : unicorn;

        var savedUnicorn = unicornRepository.save(unicornWithId);
        publishUnicornEvent(savedUnicorn, UnicornEventType.UNICORN_CREATED);

        logger.info("[{}] Created unicorn with ID: {}", requestId, savedUnicorn.getId());
        return savedUnicorn;
    }

    public List<Unicorn> getAllUnicorns() {
        var unicorns = StreamSupport
            .stream(unicornRepository.findAll().spliterator(), false)
            .toList();

        // Java 21 Sequenced Collections - cleaner than index-based access
        if (!unicorns.isEmpty()) {
            logger.debug("First unicorn: {}, Last unicorn: {}",
                unicorns.getFirst().getName(),  // Instead of unicorns.get(0)
                unicorns.getLast().getName());  // Instead of unicorns.get(size-1)
        }

        return unicorns;
    }

    private void publishUnicornEvent(Unicorn unicorn, UnicornEventType eventType) {
        try {
            unicornPublisher.publish(unicorn, eventType).get();
        } catch (InterruptedException _) {
            // Java 22 Unnamed Variables - exception not used
            Thread.currentThread().interrupt();
        } catch (ExecutionException _) {
            // Java 22 Unnamed Variables - exception not used, just log
            String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
            logger.error("[{}] Failed to publish {} event for unicorn ID: {}",
                    requestId, eventType, unicorn.getId());
        }
    }
}
```

### 4. Test Infrastructure

**Why This Structure?**
- 4 files instead of 9: reduces cognitive load
- Single annotation entry point: `@TestInfrastructure`
- AssertJ: fluent, readable assertions
- Correct LocalStack services: EventBridge (not S3/DynamoDB)

```
src/test/java/com/unicorn/store/integration/
├── TestInfrastructure.java           # Single annotation for test config
├── TestInfrastructureInitializer.java # Container setup logic
├── UnicornControllerTest.java         # Integration tests
└── StoreApplicationTest.java          # Context loading test
```

**TestInfrastructure Annotation:**

```java
/**
 * Single entry point for test infrastructure configuration.
 *
 * Combines:
 * - Spring Boot test configuration
 * - Testcontainers initialization
 * - Profile activation (if needed)
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@ExtendWith(TestInfrastructureInitializer.class)
public @interface TestInfrastructure {
}
```

**TestInfrastructureInitializer:**

```java
/**
 * Initializes test infrastructure with Testcontainers 2.0.
 *
 * Features:
 * - PostgreSQL container for database
 * - LocalStack with CLOUDWATCHEVENTS for EventBridge testing
 * - Container reuse for faster test execution
 * - H2 fallback when Docker unavailable
 *
 * Note: Testcontainers 2.0 uses new package structure:
 * - org.testcontainers.postgresql.PostgreSQLContainer
 * - org.testcontainers.localstack.LocalStackContainer
 */
import org.testcontainers.postgresql.PostgreSQLContainer;  // TC 2.0 package
import org.testcontainers.localstack.LocalStackContainer;  // TC 2.0 package

public class TestInfrastructureInitializer implements BeforeAllCallback {

    private static PostgreSQLContainer<?> postgres;
    private static LocalStackContainer localstack;

    @Override
    public void beforeAll(ExtensionContext context) {
        try {
            DockerClientFactory.instance().client();
            initializeTestcontainers();
        } catch (Exception _) {
            // Java 22 Unnamed Variables
            initializeH2Fallback();
        }
    }

    private void initializeTestcontainers() {
        if (postgres == null) {
            postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:15-alpine"))
                .withDatabaseName("unicornstore")
                .withUsername("unicorn")
                .withPassword("unicorn")
                .withReuse(true);  // Container reuse for faster tests
            postgres.start();

            System.setProperty("spring.datasource.url", postgres.getJdbcUrl());
            System.setProperty("spring.datasource.username", postgres.getUsername());
            System.setProperty("spring.datasource.password", postgres.getPassword());
        }

        if (localstack == null) {
            // CLOUDWATCHEVENTS for EventBridge - NOT S3/DynamoDB
            localstack = new LocalStackContainer(DockerImageName.parse("localstack/localstack:3.0"))
                .withServices(LocalStackContainer.Service.CLOUDWATCHEVENTS)
                .withReuse(true);
            localstack.start();

            System.setProperty("aws.endpointUrl", localstack.getEndpoint().toString());
        }
    }
}
```

### 5. Dockerfile Patterns

**Container Optimization Hierarchy:**

```
# SIZE OPTIMIZATION (workshop progression)
Dockerfile_00_initial      → ~800MB (bad starting point for comparison)
Dockerfile_01_build        → ~700MB (build in Docker)
Dockerfile_02_multistage   → ~400MB (runtime image only)
Dockerfile_03_custom_jre   → ~150MB (jlink custom JRE)
Dockerfile_04_spring_layers→ ~400MB (faster rebuilds)
Dockerfile_05_native       → ~80MB  (Mandrel native image)

# STARTUP OPTIMIZATION
Dockerfile_06_cds          → ~5s startup (Class Data Sharing)
Dockerfile_07_aot_leyden   → ~2s startup (Java 25 Leyden AOT)
Dockerfile_08_crac         → ~100ms startup (Checkpoint/Restore)

# OBSERVABILITY
Dockerfile_09_otel         → OpenTelemetry instrumentation
Dockerfile_10_profiler     → Async profiler for performance analysis
```

**Key Dockerfile Patterns:**

```dockerfile
# Pattern 1: Compact Object Headers (all Dockerfiles)
# Reduces object header from 96-128 bits to 64 bits
# ~10-15% memory reduction, especially beneficial for many small objects
ENTRYPOINT ["java", "-XX:+UseCompactObjectHeaders", "-jar", "app.jar"]

# Pattern 2: Multi-architecture support (async profiler)
ARG TARGETARCH
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x64") && \
    wget https://github.com/async-profiler/.../async-profiler-4.2.1-linux-${ARCH}.tar.gz

# Pattern 3: jlink compression (custom JRE)
# Use zip-6 instead of deprecated --compress 2
RUN jlink --compress zip-6 --strip-java-debug-attributes \
    --no-header-files --no-man-pages --output custom-jre \
    --add-modules $(cat jre-deps.info)

# Pattern 4: Non-root user (security)
RUN groupadd --system spring -g 1000 && \
    adduser spring -u 1000 -g 1000
USER 1000:1000

# Pattern 5: ENTRYPOINT not CMD (proper signal handling)
ENTRYPOINT ["java", "-jar", "app.jar"]  # Correct
# CMD ["java", "-jar", "app.jar"]       # Incorrect - doesn't receive signals properly
```

## Data Models

### Unicorn Entity

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | String (UUID) | Primary Key | Unique identifier |
| name | String | Required, non-blank | Unicorn's name |
| age | String | Optional | Unicorn's age |
| size | String | Optional | Unicorn's size |
| type | String | Required, non-blank | Unicorn's type |

### UnicornEventType Enum

```java
public enum UnicornEventType {
    UNICORN_CREATED,
    UNICORN_UPDATED,
    UNICORN_DELETED
}
```

### Database Schema (PostgreSQL)

```sql
CREATE TABLE IF NOT EXISTS unicorns (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    age VARCHAR(50),
    size VARCHAR(50),
    type VARCHAR(100) NOT NULL
);
```

### Database Schema (H2 Fallback)

```sql
-- H2-compatible schema for testing without Docker
CREATE TABLE IF NOT EXISTS unicorns (
    id VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY,  -- H2 function, not gen_random_uuid()
    name VARCHAR(255) NOT NULL,
    age VARCHAR(50),
    size VARCHAR(50),
    type VARCHAR(100) NOT NULL
);
```



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Based on the prework analysis of acceptance criteria, the following properties are testable and provide unique validation value:

### Property 1: Constructor Validation Rejects Invalid Input

*For any* string that is null or consists entirely of whitespace characters used as the `name` parameter, AND *for any* string that is null or consists entirely of whitespace characters used as the `type` parameter, constructing a Unicorn SHALL throw an `IllegalArgumentException`.

**Validates: Requirements 2.2, 2.3**

**Rationale:** This property ensures the Flexible Constructor Bodies (JEP 513) validation works correctly. By generating random invalid inputs (null, empty string, whitespace-only strings), we verify that invalid Unicorn objects can never be created.

**Test Strategy:**
- Generate random strings that are null, empty, or whitespace-only
- Attempt to construct Unicorn with invalid name (valid type)
- Attempt to construct Unicorn with invalid type (valid name)
- Verify IllegalArgumentException is thrown in all cases

### Property 2: JSON Serialization Round-Trip

*For any* valid Unicorn object, serializing to JSON and deserializing back SHALL produce an object with equivalent field values.

**Validates: Requirements 9.3**

**Rationale:** This round-trip property ensures the @JsonProperty annotations are correctly configured and that no data is lost during serialization/deserialization. This is critical for the REST API.

**Test Strategy:**
- Generate random valid Unicorn objects (with valid name, type, and random age/size)
- Serialize to JSON using ObjectMapper
- Deserialize back to Unicorn
- Verify all fields match original

### Property 3: Equals/HashCode Contract

*For any* two Unicorn objects with the same ID, `equals()` SHALL return true. *For any* single Unicorn object, multiple calls to `hashCode()` SHALL return the same value.

**Validates: Requirements 9.4**

**Rationale:** The equals/hashCode contract is fundamental for correct behavior in collections (HashMap, HashSet). This property ensures the entity behaves correctly when used in JPA contexts and collections.

**Test Strategy:**
- Generate random Unicorn, create copy with same ID
- Verify equals returns true for same-ID unicorns
- Verify hashCode is consistent across multiple calls
- Verify equals is reflexive (u.equals(u) == true)

### Property 4: Event Publishing on CRUD Operations

*For any* successful create, update, or delete operation on a Unicorn, a corresponding event SHALL be published to EventBridge with the correct event type.

**Validates: Requirements 17.1**

**Rationale:** This property ensures the EventBridge integration works correctly for all CRUD operations. It validates that the event-driven architecture is properly implemented.

**Test Strategy:**
- Generate random valid Unicorn
- Perform create operation, verify UNICORN_CREATED event published
- Perform update operation, verify UNICORN_UPDATED event published
- Perform delete operation, verify UNICORN_DELETED event published
- Use LocalStack to capture and verify events

### Property 5: Graceful Degradation When EventBridge Unavailable

*For any* CRUD operation when EventBridge is unavailable or returns an error, the operation SHALL still complete successfully (data persisted/updated/deleted) and the error SHALL be logged.

**Validates: Requirements 17.4**

**Rationale:** This property ensures the application doesn't fail user operations due to event publishing failures. This is critical for production resilience.

**Test Strategy:**
- Configure EventBridge client to fail (invalid endpoint or mock failure)
- Perform create/update/delete operations
- Verify operations succeed (data changes persisted)
- Verify error is logged (not thrown)

### Property 6: Request ID Uniqueness

*For any* set of concurrent HTTP requests, each request SHALL receive a unique request ID bound to the Scoped Value.

**Validates: Requirements 1.1, 1.2**

**Rationale:** This property ensures the Scoped Values implementation correctly generates and propagates unique request IDs. This is essential for request tracing and debugging.

**Test Strategy:**
- Send multiple concurrent requests
- Capture request IDs from responses or logs
- Verify all request IDs are unique (no duplicates)

## Error Handling

### HTTP Error Responses

| Scenario | HTTP Status | Response Body |
|----------|-------------|---------------|
| Unicorn not found | 404 Not Found | Error message with ID |
| Invalid unicorn data | 400 Bad Request | Validation error details |
| Server error | 500 Internal Server Error | Generic error message |
| Validation errors | 400 Bad Request | List of field errors |

### Exception Hierarchy

```java
// Application-specific exceptions
ResourceNotFoundException extends RuntimeException
    → Mapped to 404 Not Found

IllegalArgumentException (from constructor validation)
    → Mapped to 400 Bad Request

// Spring exceptions
MethodArgumentNotValidException
    → Mapped to 400 Bad Request with field errors
```

### EventBridge Error Handling

```java
private void publishUnicornEvent(Unicorn unicorn, UnicornEventType eventType) {
    try {
        unicornPublisher.publish(unicorn, eventType).get();
    } catch (InterruptedException _) {
        // Java 22 Unnamed Variables - restore interrupt status
        Thread.currentThread().interrupt();
    } catch (ExecutionException _) {
        // Log but don't fail the operation
        logger.error("[{}] Failed to publish {} event for unicorn ID: {}",
                RequestContext.REQUEST_ID.orElse("no-request-id"),
                eventType,
                unicorn.getId());
    }
}
```

### H2 Fallback Error Handling

```java
@Override
public void beforeAll(ExtensionContext context) {
    try {
        DockerClientFactory.instance().client();
        logger.info("Docker available, using Testcontainers");
        initializeTestcontainers();
    } catch (Exception _) {
        // Java 22 Unnamed Variables
        logger.warn("Docker unavailable, falling back to H2");
        initializeH2Fallback();
    }
}
```

## Testing Strategy

### Dual Testing Approach

This application uses both **unit tests** and **property-based tests** for comprehensive coverage:

| Test Type | Purpose | Coverage |
|-----------|---------|----------|
| Unit Tests | Specific examples, edge cases, error conditions | Controller endpoints, service methods |
| Property Tests | Universal properties across all inputs | Validation, serialization, contracts |

### Property-Based Testing Configuration

**Library:** jqwik (Java property-based testing library)

**Configuration:**
- Minimum 100 iterations per property test
- Each test tagged with property number and requirements reference

**Example Property Test:**

```java
@Property(tries = 100)
@Tag("Feature: java25-spring-modernization, Property 1: Constructor Validation")
void constructorRejectsInvalidName(@ForAll("invalidStrings") String invalidName) {
    // Validates: Requirements 2.2
    assertThatThrownBy(() -> new Unicorn(invalidName, "10", "Big", "standard"))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("name");
}

@Provide
Arbitrary<String> invalidStrings() {
    return Arbitraries.oneOf(
        Arbitraries.just(null),
        Arbitraries.just(""),
        Arbitraries.just("   "),
        Arbitraries.strings().whitespace().ofMinLength(1)
    );
}
```

### Unit Test Structure

```java
@TestInfrastructure
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UnicornControllerTest {

    @LocalServerPort
    private int port;

    private WebTestClient webTestClient;

    @BeforeEach
    void setUp() {
        webTestClient = WebTestClient.bindToServer()
            .baseUrl("http://localhost:" + port)
            .build();
    }

    @Test
    void shouldCreateUnicorn() {
        Unicorn unicorn = new Unicorn("TestUnicorn", "10", "Big", "standard");

        webTestClient.post()
            .uri("/unicorns")
            .bodyValue(unicorn)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Unicorn.class)
            .value(u -> {
                assertThat(u.getId()).isNotNull();
                assertThat(u.getName()).isEqualTo("TestUnicorn");
            });
    }
}
```

### Test Dependencies

```xml
<!-- Property-based testing -->
<dependency>
    <groupId>net.jqwik</groupId>
    <artifactId>jqwik</artifactId>
    <version>1.9.3</version>
    <scope>test</scope>
</dependency>

<!-- AssertJ for fluent assertions -->
<dependency>
    <groupId>org.assertj</groupId>
    <artifactId>assertj-core</artifactId>
    <scope>test</scope>
</dependency>
```

### Test File Structure

```
src/test/java/com/unicorn/store/
├── integration/
│   ├── TestInfrastructure.java           # Annotation
│   ├── TestInfrastructureInitializer.java # Container setup
│   ├── UnicornControllerTest.java         # Integration tests
│   └── StoreApplicationTest.java          # Context test
└── property/
    ├── UnicornValidationPropertyTest.java # Property 1
    ├── UnicornSerializationPropertyTest.java # Property 2
    ├── UnicornEqualsPropertyTest.java     # Property 3
    ├── EventPublishingPropertyTest.java   # Property 4, 5
    └── RequestContextPropertyTest.java    # Property 6
```

### Container Optimization Testing

Each Dockerfile should be tested for:
1. **Build success** on both ARM64 and x64
2. **Application startup** with expected JVM flags
3. **Health endpoint** accessibility
4. **Memory usage** with Compact Object Headers enabled

```bash
# Build and test pattern
docker build -f Dockerfile_XX_name -t test-image .
docker run -d -p 8080:8080 test-image
curl http://localhost:8080/actuator/health
docker stats --no-stream test-image
```
