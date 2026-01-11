# Unicorn Store - Java 25 + Spring Boot 4

A REST API for managing unicorns, built to showcase modern Java features and container optimization techniques.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      HTTP Request                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  RequestContextFilter                                       │
│  - Generates unique request ID                              │
│  - Binds to ScopedValue (JEP 506) for request duration      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  UnicornController / ThreadManagementController             │
│  - REST endpoints: GET/POST/PUT/DELETE /unicorns            │
│  - Thread management: /api/threads/*                        │
│  - Input validation, error handling                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  UnicornService / ThreadGeneratorService                    │
│  - Business logic, validation                               │
│  - Reads request ID from ScopedValue for log correlation    │
│  - Publishes events to EventBridge                          │
│  - Platform thread generation for profiling                 │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  UnicornRepository      │     │  UnicornPublisher       │
│  - Spring Data JPA      │     │  - EventBridge async    │
│  - PostgreSQL           │     │  - CRUD events          │
└─────────────────────────┘     └─────────────────────────┘
```

## Project Structure

```
src/main/java/com/unicorn/store/
├── StoreApplication.java              # Spring Boot entry point
├── context/
│   └── RequestContext.java            # ScopedValue holder (JEP 506)
├── filter/
│   └── RequestContextFilter.java      # Binds request ID to ScopedValue
├── controller/
│   ├── UnicornController.java         # REST API endpoints
│   └── ThreadManagementController.java # Thread profiling endpoints
├── service/
│   ├── UnicornService.java            # Business logic
│   └── ThreadGeneratorService.java    # Platform thread generator
├── data/
│   ├── UnicornRepository.java         # Spring Data JPA
│   └── UnicornPublisher.java          # EventBridge integration
├── model/
│   ├── Unicorn.java                   # JPA entity
│   └── UnicornEventType.java          # Event type enum
├── exceptions/
│   ├── ResourceNotFoundException.java # 404 exception
│   └── PublisherException.java        # EventBridge exception
├── config/
│   └── MonitoringConfig.java          # Metrics for EKS/ECS
└── monitoring/
    └── ThreadMonitoringMBean.java     # JMX thread stats
```

## Modern Java Features

| Feature | JEP | Location | Description |
|---------|-----|----------|-------------|
| Scoped Values | [506](https://openjdk.org/jeps/506) | `RequestContext`, `RequestContextFilter` | Thread-safe request context without ThreadLocal |
| Flexible Constructor Bodies | [513](https://openjdk.org/jeps/513) | `Unicorn` constructor | Validation before field assignment |
| Unnamed Variables | 456 | `UnicornService`, `ThreadGeneratorService`, `TestInfrastructureInitializer` | `catch (Exception _)` when variable unused |
| Sequenced Collections | 431 | `UnicornService.getAllUnicorns()` | `getFirst()`, `getLast()` methods |
| Pattern Matching | 441 | `UnicornService.validateUnicorn()`, `ThreadManagementController` | Switch with guarded patterns, sealed types |
| Virtual Threads | 444 | `application.yaml` | `spring.threads.virtual.enabled: true` |
| Records | 395 | `ThreadManagementController` | `Success`, `Failure` result types |
| Sealed Types | 409 | `ThreadManagementController` | `Result` interface with `Success`/`Failure` |
| Compact Object Headers | [450](https://openjdk.org/jeps/450) | `Dockerfile` | `-XX:+UseCompactObjectHeaders` JVM flag |

## Testing

```bash
# Run all tests
mvn test

# Tests use Testcontainers 2.0 with H2 fallback when Docker unavailable
```

**Test Infrastructure:**
- `@TestInfrastructure` - unified annotation for integration tests
- PostgreSQL via Testcontainers 2.0, H2 fallback without Docker
- LocalStack for EventBridge
- Property-based tests with jqwik for validation logic

**Test Categories:**
- Integration tests: `StoreApplicationTest`, `UnicornControllerTest`
- Property tests: `UnicornValidationPropertyTest`, `UnicornEqualsPropertyTest`, `RequestContextPropertyTest`

## Building

```bash
mvn package                    # Standard JAR
mvn package -Pnative           # Native image (GraalVM 25)
mvn jib:dockerBuild            # Container with Jib
docker build -t unicorn-store . # Container with Dockerfile
```

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Spring Boot | 4.0.1 | Application framework |
| AWS SDK | 2.40.15 | EventBridge integration |
| Testcontainers | 2.0.3 | Integration testing |
| jqwik | 1.9.3 | Property-based testing |
| CRaC | 1.5.0 | Checkpoint/Restore support |
| PostgreSQL | runtime | Database driver |
| Micrometer Prometheus | - | Metrics export |

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Welcome message |
| GET | `/unicorns` | List all unicorns |
| POST | `/unicorns` | Create unicorn |
| GET | `/unicorns/{id}` | Get by ID |
| PUT | `/unicorns/{id}` | Update unicorn |
| DELETE | `/unicorns/{id}` | Delete unicorn |
| POST | `/api/threads/start?count=N` | Start N platform threads |
| POST | `/api/threads/stop` | Stop all threads |
| GET | `/api/threads/count` | Get active thread count |
| GET | `/actuator/health` | Health check |
| GET | `/actuator/prometheus` | Metrics |

## Configuration Highlights

- Virtual threads enabled for improved scalability
- HikariCP pool size: 1 (workshop demo)
- Graceful shutdown for container orchestration
- Kubernetes-style health probes (liveness/readiness)
- EKS/ECS-aware metrics tagging (cluster, namespace, pod/task ID)
- JMX disabled for reduced memory footprint

## Container Images

**Dockerfile:** Multi-stage build with Amazon Corretto 25 on AL2023
- Uses `-XX:+UseCompactObjectHeaders` for reduced memory footprint
- Runs as non-root user (UID 1000)

**Jib:** Direct container build without Dockerfile
- Base image: `public.ecr.aws/docker/library/amazoncorretto:25-al2023`
