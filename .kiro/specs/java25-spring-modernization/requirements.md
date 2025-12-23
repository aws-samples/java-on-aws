# Requirements Document

## Introduction

This specification defines the requirements for the unicorn-store-spring-java25 application as a **showcase workshop application** demonstrating Java 25, Spring Framework 7, and Spring Boot 4 best practices. The application serves as the centerpiece of an AWS workshop showing Java deployment options (EKS, ECS) and container optimizations (multi-stage builds, jlink, native images, CDS, CRaC, AOT).

When a Java/Spring developer sees this application, they should think:
- "This is how modern Java 25 code should look"
- "This is proper Spring Boot 4 / Spring 7 architecture"
- "This is production-ready, not just a demo"

## Glossary

- **Application**: The unicorn-store-spring-java25 Spring Boot application
- **Scoped_Values**: Java 25 feature (JEP 506) for sharing immutable data within and across threads
- **Flexible_Constructor_Bodies**: Java 25 feature (JEP 513) allowing statements before super() calls
- **Compact_Object_Headers**: Java 25 feature (JEP 519) reducing object header size from 96-128 bits to 64 bits
- **Sealed_Types**: Java feature for restricting which classes can extend/implement a type
- **Pattern_Matching**: Java feature for conditional extraction of data from objects
- **Virtual_Threads**: Java 21+ lightweight threads managed by the JVM
- **EventBridge**: AWS service for serverless event routing
- **LocalStack**: Local AWS cloud stack for testing
- **Testcontainers**: Java library for lightweight, throwaway test containers
- **WebTestClient**: Spring WebFlux reactive test client
- **AssertJ**: Fluent assertion library for Java
- **CDS**: Class Data Sharing - JVM feature for faster startup
- **CRaC**: Coordinated Restore at Checkpoint - JVM feature for instant startup
- **AOT**: Ahead-of-Time compilation
- **jlink**: JDK tool for creating custom runtime images
- **Mandrel**: GraalVM distribution for building native images

## Requirements

### Requirement 1: Java 25 Scoped Values for Request Context

**User Story:** As a workshop attendee, I want to see how Scoped Values replace ThreadLocal for request context propagation, so that I can understand modern Java 25 patterns for context management.

#### Acceptance Criteria

1. THE Application SHALL use Scoped Values (JEP 506) for propagating request context across method calls
2. WHEN a request is received, THE Application SHALL generate a unique request ID and bind it to a ScopedValue
3. THE Application SHALL access the request ID from any service layer method without explicit parameter passing
4. THE Application SHALL demonstrate Scoped Values in logging to show request tracing capability

### Requirement 2: Java 25 Flexible Constructor Bodies for Validation

**User Story:** As a workshop attendee, I want to see how Flexible Constructor Bodies enable pre-super() validation, so that I can understand modern Java 25 constructor patterns.

#### Acceptance Criteria

1. THE Unicorn model SHALL use Flexible Constructor Bodies (JEP 513) for input validation before field assignment
2. WHEN a Unicorn is constructed with null or blank name, THE constructor SHALL throw IllegalArgumentException before any field assignment
3. WHEN a Unicorn is constructed with null or blank type, THE constructor SHALL throw IllegalArgumentException before any field assignment
4. THE validation logic SHALL execute before the implicit super() call

### Requirement 3: Pattern Matching for Validation

**User Story:** As a workshop attendee, I want to see how Pattern Matching with switch expressions simplifies validation logic, so that I can understand modern Java patterns for conditional logic.

#### Acceptance Criteria

1. THE UnicornService SHALL use pattern matching switch expressions for unicorn validation (already present, keep and document)
2. THE validation switch SHALL use guarded patterns (case Unicorn u when condition) for null/blank checks
3. THE pattern matching SHALL demonstrate exhaustive switch handling with default case

### Requirement 4: Modern Java Language Features

**User Story:** As a workshop attendee, I want to see modern Java language features used consistently, so that I can learn idiomatic Java 25 coding patterns.

#### Acceptance Criteria

1. THE Application SHALL use unnamed variables (Java 22) in catch blocks where the exception is not used
2. THE Application SHALL use Sequenced Collections methods (getFirst(), getLast()) instead of index-based access
3. THE Application SHALL use record patterns in instanceof checks where applicable
4. THE Application SHALL use text blocks for multi-line strings

### Requirement 5: Virtual Threads Configuration

**User Story:** As a workshop attendee, I want to see proper Virtual Threads configuration, so that I can understand how Spring Boot 4 leverages Java 21+ virtual threads.

#### Acceptance Criteria

1. THE Application SHALL enable Virtual Threads via Spring Boot configuration
2. THE Application SHALL handle all HTTP requests on Virtual Threads
3. THE Application SHALL demonstrate Virtual Thread usage in service layer operations

### Requirement 6: Spring Boot 4 / Spring Framework 7 Architecture

**User Story:** As a workshop attendee, I want to see proper Spring Boot 4 architecture patterns, so that I can understand modern Spring application structure.

#### Acceptance Criteria

1. THE Application SHALL use Jakarta EE 11 APIs (jakarta.* packages)
2. THE Application SHALL configure Spring Actuator with appropriate endpoint exposure for production
3. THE Application SHALL use constructor injection for all dependencies
4. THE Application SHALL use Spring Boot 4 configuration properties patterns

### Requirement 7: Clean Test Architecture

**User Story:** As a workshop attendee, I want to see a clean, minimal test structure, so that I can understand proper Spring Boot testing patterns.

#### Acceptance Criteria

1. THE test infrastructure SHALL consist of exactly 4 files: TestInfrastructure annotation, TestInfrastructureInitializer, UnicornControllerTest, and StoreApplicationTest
2. THE TestInfrastructure annotation SHALL be the single entry point for test configuration
3. THE tests SHALL use AssertJ assertions instead of raw assert statements
4. THE tests SHALL use WebTestClient for HTTP endpoint testing
5. WHEN Docker is unavailable, THE test infrastructure SHALL fall back to H2 database with working schema

### Requirement 8: Correct AWS Integration Testing

**User Story:** As a workshop attendee, I want to see correct AWS service integration in tests, so that I can understand proper LocalStack usage patterns.

#### Acceptance Criteria

1. THE LocalStack container SHALL be configured with CLOUDWATCHEVENTS service for EventBridge testing
2. THE LocalStack container SHALL NOT be configured with S3 or DynamoDB services (not used by application)
3. THE LocalStack container SHALL enable container reuse for faster test execution
4. THE test infrastructure SHALL set correct AWS endpoint properties for LocalStack

### Requirement 9: Clean Unicorn Model

**User Story:** As a workshop attendee, I want to see a clean domain model without duplicate code, so that I can understand proper JPA entity design.

#### Acceptance Criteria

1. THE Unicorn entity SHALL have only standard JavaBean accessors (getId, getName, etc.)
2. THE Unicorn entity SHALL NOT have duplicate record-style accessors (id(), name(), etc.)
3. THE Unicorn entity SHALL use @JsonProperty annotations for JSON serialization
4. THE Unicorn entity SHALL implement proper equals/hashCode based on ID

### Requirement 10: Container Optimization - Compact Object Headers

**User Story:** As a workshop attendee, I want to see JVM optimizations for container deployments, so that I can understand memory optimization techniques.

#### Acceptance Criteria

1. ALL Dockerfiles SHALL include -XX:+UseCompactObjectHeaders JVM flag for 10-15% memory reduction
2. THE JVM flags SHALL be documented with comments explaining their purpose
3. THE optimization SHALL be compatible with both ARM64 (Graviton) and x64 architectures

### Requirement 11: Container Optimization - Multi-Architecture Support

**User Story:** As a workshop attendee, I want all container images to work on both ARM64 and x64, so that I can deploy on Graviton instances for cost savings.

#### Acceptance Criteria

1. ALL Dockerfiles SHALL support both ARM64 (Graviton) and x64 architectures
2. THE async-profiler Dockerfile SHALL use TARGETARCH to download correct architecture binary
3. THE native image Dockerfile SHALL use Mandrel builder that supports both architectures

### Requirement 12: Container Optimization - Proper Dockerfile Patterns

**User Story:** As a workshop attendee, I want to see proper Dockerfile patterns, so that I can understand container best practices.

#### Acceptance Criteria

1. ALL Dockerfiles SHALL use ENTRYPOINT instead of CMD for the main application
2. ALL Dockerfiles SHALL include -DskipTests in Maven build commands
3. THE jlink Dockerfile SHALL use --compress zip-6 instead of deprecated --compress 2
4. THE SOCI Dockerfile SHALL place COPY commands before USER directive
5. ALL Dockerfiles SHALL create non-root user for running the application

### Requirement 13: Container Optimization - Native Image

**User Story:** As a workshop attendee, I want to see proper native image configuration, so that I can understand GraalVM native compilation.

#### Acceptance Criteria

1. THE native image Dockerfile SHALL be named Dockerfile_05_native (not Dockerfile_05_GraalVM)
2. THE native image SHALL be built using Mandrel builder image
3. THE native image SHALL use ENTRYPOINT for application startup
4. THE native image build SHALL skip tests during compilation

### Requirement 14: Updated Dependencies

**User Story:** As a workshop attendee, I want to see current dependency versions, so that I can use the application as a reference for my projects.

#### Acceptance Criteria

1. THE Application SHALL use AWS SDK version 2.40.14 or later
2. THE Application SHALL NOT require --add-opens JVM flags for test execution
3. THE Application SHALL use Testcontainers version 2.0.3 or later with updated module coordinates

### Requirement 15: H2 Database Fallback

**User Story:** As a workshop attendee, I want tests to work without Docker, so that I can run tests in environments where Docker is unavailable.

#### Acceptance Criteria

1. WHEN Docker is unavailable, THE test infrastructure SHALL configure H2 in-memory database
2. THE H2 schema.sql SHALL use H2-compatible UUID generation (RANDOM_UUID() not gen_random_uuid())
3. THE H2 fallback SHALL provide mock AWS endpoint configuration
4. THE Application SHALL log clearly when falling back to H2

### Requirement 16: Production-Ready Configuration

**User Story:** As a workshop attendee, I want to see production-ready configuration patterns, so that I can understand how to configure Spring Boot for production.

#### Acceptance Criteria

1. THE Application SHALL expose health, info, prometheus, and threaddump actuator endpoints
2. THE Application SHALL configure liveness and readiness probes for Kubernetes
3. THE Application SHALL use appropriate connection pool settings for containerized deployment
4. THE Application SHALL disable JMX for container deployments

### Requirement 17: EventBridge Integration

**User Story:** As a workshop attendee, I want to see proper EventBridge integration, so that I can understand AWS event-driven architecture patterns.

#### Acceptance Criteria

1. THE Application SHALL publish unicorn lifecycle events (created, updated, deleted) to EventBridge
2. THE UnicornPublisher SHALL use AWS SDK v2 EventBridge client
3. THE event publishing SHALL be asynchronous and non-blocking
4. WHEN event publishing fails, THE Application SHALL log the error but not fail the operation

### Requirement 18: Code Quality and Documentation

**User Story:** As a workshop attendee, I want to see well-documented, high-quality code, so that I can use it as a learning reference.

#### Acceptance Criteria

1. THE Application SHALL include comments explaining Java 25 features where they are used
2. THE Application SHALL use meaningful variable and method names
3. THE Application SHALL follow consistent code formatting
4. THE Dockerfiles SHALL include comments explaining each optimization technique
5. THE Application SHALL use Spotless with Palantir Java Format for automated code formatting
6. THE pom.xml SHALL be organized with sortpom plugin for consistent dependency ordering
7. THE application.yaml SHALL be organized with logical sections and explanatory comments

### Requirement 19: Clean Configuration for Microservices

**User Story:** As a workshop attendee, I want to see production-ready microservice configuration, so that I can understand best practices for containerized Java applications.

#### Acceptance Criteria

1. THE Application SHALL configure graceful shutdown for container orchestration
2. THE Application SHALL configure appropriate connection pool sizes for containerized deployment
3. THE Application SHALL configure proper request timeouts
4. THE Application SHALL use structured logging suitable for container environments
5. THE Application SHALL externalize all environment-specific configuration via environment variables
6. THE pom.xml SHALL NOT contain unused dependencies
