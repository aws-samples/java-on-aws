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
│  UnicornController                                          │
│  - REST endpoints: GET/POST/PUT/DELETE /unicorns            │
│  - Input validation, error handling                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  UnicornService                                             │
│  - Business logic, validation                               │
│  - Reads request ID from ScopedValue for log correlation    │
│  - Publishes events to EventBridge                          │
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
├── StoreApplication.java          # Spring Boot entry point
├── context/
│   └── RequestContext.java        # ScopedValue holder (JEP 506)
├── filter/
│   └── RequestContextFilter.java  # Binds request ID to ScopedValue
├── controller/
│   └── UnicornController.java     # REST API endpoints
├── service/
│   └── UnicornService.java        # Business logic
├── data/
│   ├── UnicornRepository.java     # Spring Data JPA
│   └── UnicornPublisher.java      # EventBridge integration
├── model/
│   └── Unicorn.java               # JPA entity
└── config/
    └── MonitoringConfig.java      # Metrics for EKS/ECS
```

## Modern Java Features

| Feature | JEP | Location | Description |
|---------|-----|----------|-------------|
| Scoped Values | [506](https://openjdk.org/jeps/506) | `RequestContext`, `RequestContextFilter` | Thread-safe request context without ThreadLocal |
| Flexible Constructor Bodies | [513](https://openjdk.org/jeps/513) | `Unicorn` constructor | Validation before super() call |
| Unnamed Variables | 456 | catch blocks | `catch (Exception _)` when variable unused |
| Sequenced Collections | 431 | `UnicornService.getAllUnicorns()` | `getFirst()`, `getLast()` methods |
| Pattern Matching | 441 | `UnicornService.validateUnicorn()` | Switch with guarded patterns |
| Virtual Threads | 444 | `application.yaml` | `spring.threads.virtual.enabled: true` |
| Text Blocks | 378 | `UnicornController` | Multi-line strings |

## Testing

```bash
# Run all tests (26 total)
mvn test

# Tests use Testcontainers 2.0 with H2 fallback when Docker unavailable
```

**Test Infrastructure:**
- `@TestInfrastructure` - unified annotation for integration tests
- PostgreSQL via Testcontainers, H2 fallback without Docker
- LocalStack for EventBridge
- Property-based tests with jqwik for validation logic

## Building

```bash
mvn package           # Standard JAR
mvn package -Pnative  # Native image (GraalVM)
mvn jib:dockerBuild   # Container with Jib
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/unicorns` | List all unicorns |
| POST | `/unicorns` | Create unicorn |
| GET | `/unicorns/{id}` | Get by ID |
| PUT | `/unicorns/{id}` | Update unicorn |
| DELETE | `/unicorns/{id}` | Delete unicorn |
| GET | `/actuator/health` | Health check |
| GET | `/actuator/prometheus` | Metrics |
