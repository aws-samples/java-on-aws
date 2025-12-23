# Implementation Plan: Java 25 + Spring Boot 4 Modernization

## Overview

This implementation plan transforms unicorn-store-spring-java25 into a showcase workshop application demonstrating Java 25, Spring Framework 7, and Spring Boot 4 best practices. Tasks are organized by priority: critical fixes first, then Java features, tests, and finally Dockerfiles.

## Tasks

- [ ] 1. Critical Fixes and Dependency Updates
  - [ ] 1.1 Update AWS SDK to version 2.40.14+
    - Update `pom.xml` AWS SDK BOM version from 2.33.4 to 2.40.14
    - _Requirements: 14.1_

  - [ ] 1.2 Remove --add-opens JVM flags from surefire plugin
    - Remove all `--add-opens` arguments from maven-surefire-plugin configuration
    - Update test dependencies if needed to eliminate illegal reflective access
    - _Requirements: 14.2_

  - [ ] 1.3 Remove unused AWS SDK dependencies
    - Remove S3 and DynamoDB dependencies from pom.xml (not used by application)
    - Keep only EventBridge and STS dependencies
    - _Requirements: 8.2_

- [ ] 2. Java 25 Scoped Values Implementation
  - [ ] 2.1 Create RequestContext class with ScopedValue
    - Create `src/main/java/com/unicorn/store/context/RequestContext.java`
    - Define `public static final ScopedValue<String> REQUEST_ID`
    - Add Javadoc explaining Scoped Values (JEP 506) benefits
    - _Requirements: 1.1, 1.3_

  - [ ] 2.2 Create RequestContextFilter
    - Create `src/main/java/com/unicorn/store/filter/RequestContextFilter.java`
    - Implement Filter interface with `ScopedValue.runWhere()` pattern
    - Generate UUID for each request and bind to REQUEST_ID
    - Add `@Order(Ordered.HIGHEST_PRECEDENCE)` for early execution
    - _Requirements: 1.2, 1.4_

  - [ ] 2.3 Update UnicornService to use Scoped Values
    - Import RequestContext and access REQUEST_ID in logging statements
    - Use `RequestContext.REQUEST_ID.orElse("no-request-id")` pattern
    - Update all logger calls to include request ID
    - _Requirements: 1.1, 1.4_

  - [ ] 2.4 Write property test for Request ID uniqueness
    - **Property 6: Request ID Uniqueness**
    - Create `src/test/java/com/unicorn/store/property/RequestContextPropertyTest.java`
    - Test that concurrent requests receive unique request IDs
    - **Validates: Requirements 1.1, 1.2**

- [ ] 3. Java 25 Flexible Constructor Bodies
  - [ ] 3.1 Update Unicorn constructor with pre-super validation
    - Add validation for null/blank name before field assignment
    - Add validation for null/blank type before field assignment
    - Add Javadoc explaining Flexible Constructor Bodies (JEP 513)
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ] 3.2 Remove duplicate record-style accessors from Unicorn
    - Remove `id()`, `name()`, `age()`, `size()`, `type()` methods
    - Keep only standard JavaBean accessors (`getId()`, `getName()`, etc.)
    - Update any code that uses record-style accessors
    - _Requirements: 9.1, 9.2_

  - [ ] 3.3 Add equals/hashCode to Unicorn entity
    - Implement `equals()` based on ID field
    - Implement `hashCode()` using class hashCode (JPA pattern)
    - _Requirements: 9.4_

  - [ ] 3.4 Write property test for constructor validation
    - **Property 1: Constructor Validation Rejects Invalid Input**
    - Create `src/test/java/com/unicorn/store/property/UnicornValidationPropertyTest.java`
    - Test null, empty, and whitespace-only strings for name and type
    - **Validates: Requirements 2.2, 2.3**

  - [ ] 3.5 Write property test for equals/hashCode contract
    - **Property 3: Equals/HashCode Contract**
    - Create `src/test/java/com/unicorn/store/property/UnicornEqualsPropertyTest.java`
    - Test reflexivity, symmetry, and hashCode consistency
    - **Validates: Requirements 9.4**

- [ ] 4. Modern Java Language Features
  - [ ] 4.1 Add unnamed variables to catch blocks
    - Update UnicornService.publishUnicornEvent() to use `catch (InterruptedException _)`
    - Update TestInfrastructureInitializer to use unnamed variables
    - Add comments explaining Java 22 unnamed variables feature
    - _Requirements: 4.1_

  - [ ] 4.2 Add Sequenced Collections usage
    - Update UnicornService.getAllUnicorns() to use `getFirst()` and `getLast()`
    - Add comments explaining Java 21 Sequenced Collections
    - _Requirements: 4.2_

  - [ ] 4.3 Verify text blocks usage
    - Confirm UnicornController welcome message uses text blocks (already present)
    - Add comments if not already documented
    - _Requirements: 4.4_

- [ ] 5. Checkpoint - Core Java Features
  - Ensure all tests pass
  - Verify application starts correctly
  - Ask the user if questions arise

- [ ] 6. Test Infrastructure Simplification
  - [ ] 6.1 Create TestInfrastructure annotation
    - Create `src/test/java/com/unicorn/store/integration/TestInfrastructure.java`
    - Combine @ExtendWith with TestInfrastructureInitializer
    - _Requirements: 7.1, 7.2_

  - [ ] 6.2 Rename and update TestInfrastructureInitializer
    - Rename from TestcontainersInfrastructureInitializer if needed
    - Update LocalStack to use CLOUDWATCHEVENTS service (not S3/DynamoDB)
    - Add `.withReuse(true)` for container reuse
    - Remove unused `dockerAvailable` variable
    - _Requirements: 8.1, 8.3_

  - [ ] 6.3 Delete redundant test infrastructure files
    - Delete `InfrastructureInitializer.java`
    - Delete `InitializeInfrastructure.java`
    - Delete `InitializeSimpleInfrastructure.java`
    - Delete `InitializeTestcontainersInfrastructure.java`
    - Delete `SimpleInfrastructureInitializer.java`
    - Delete `TestApplication.java` if not needed
    - Delete `application-test.yaml` if exists
    - _Requirements: 7.1_

  - [ ] 6.4 Update UnicornControllerTest
    - Replace `@InitializeTestcontainersInfrastructure` with `@TestInfrastructure`
    - Remove `@ActiveProfiles("test")` if not needed
    - Replace raw `assert` statements with AssertJ assertions
    - _Requirements: 7.2, 7.3, 7.4_

  - [ ] 6.5 Fix H2 fallback schema
    - Update `src/test/resources/schema.sql` to use `RANDOM_UUID()` instead of `gen_random_uuid()`
    - Ensure schema works with both PostgreSQL and H2
    - _Requirements: 15.1, 15.2_

  - [ ] 6.6 Write property test for JSON serialization
    - **Property 2: JSON Serialization Round-Trip**
    - Create `src/test/java/com/unicorn/store/property/UnicornSerializationPropertyTest.java`
    - Test serialize → deserialize produces equivalent object
    - **Validates: Requirements 9.3**

- [ ] 7. EventBridge Integration Testing
  - [ ] 7.1 Verify UnicornPublisher uses EventBridge correctly
    - Confirm EventBridge client configuration
    - Ensure async publishing pattern is correct
    - _Requirements: 17.1, 17.2, 17.3_

  - [ ] 7.2 Update error handling for event publishing failures
    - Ensure errors are logged but don't fail operations
    - Use unnamed variables in catch blocks
    - _Requirements: 17.4_

  - [ ] 7.3 Write property test for event publishing
    - **Property 4: Event Publishing on CRUD Operations**
    - Create `src/test/java/com/unicorn/store/property/EventPublishingPropertyTest.java`
    - Test create/update/delete operations publish correct events
    - **Validates: Requirements 17.1**

  - [ ] 7.4 Write property test for graceful degradation
    - **Property 5: Graceful Degradation When EventBridge Unavailable**
    - Test operations succeed even when EventBridge fails
    - **Validates: Requirements 17.4**

- [ ] 8. Checkpoint - Tests Complete
  - Ensure all unit tests pass
  - Ensure all property tests pass (100 iterations each)
  - Ask the user if questions arise

- [ ] 9. Dockerfile Improvements - Size Optimization
  - [ ] 9.1 Fix Dockerfile_04_optimized_JVM
    - Change `--compress 2` to `--compress zip-6`
    - Add `-DskipTests` to Maven build
    - Add `-XX:+UseCompactObjectHeaders` to ENTRYPOINT
    - Add comments explaining jlink and Compact Object Headers
    - _Requirements: 10.1, 12.2, 12.3_

  - [ ] 9.2 Rename and fix Dockerfile_05_GraalVM
    - Rename to `Dockerfile_05_native`
    - Change CMD to ENTRYPOINT
    - Add `-DskipTests` to Maven build (use `-Dmaven.test.skip=true`)
    - Add comments explaining native image benefits
    - _Requirements: 12.1, 13.1, 13.3, 13.4_

  - [ ] 9.3 Fix Dockerfile_06_SOCI
    - Move COPY commands before USER directive
    - Add `-XX:+UseCompactObjectHeaders` to ENTRYPOINT
    - _Requirements: 10.1, 12.4_

- [ ] 10. Dockerfile Improvements - Startup Optimization
  - [ ] 10.1 Update Dockerfile_08_CDS
    - Ensure ENTRYPOINT is used (not CMD)
    - Add `-XX:+UseCompactObjectHeaders`
    - Add comments explaining CDS benefits
    - _Requirements: 10.1, 12.1_

  - [ ] 10.2 Update Dockerfile_09_CRaC
    - Ensure ENTRYPOINT is used (not CMD)
    - Add `-XX:+UseCompactObjectHeaders`
    - Add comments explaining CRaC benefits
    - _Requirements: 10.1, 12.1_

- [ ] 11. Dockerfile Improvements - Observability
  - [ ] 11.1 Verify Dockerfile_10_async_profiler multi-arch support
    - Confirm TARGETARCH is used correctly for ARM64/x64
    - Verify async-profiler version is 4.2.1
    - Add `-XX:+UseCompactObjectHeaders` to ENTRYPOINT
    - Add comments explaining profiler usage
    - _Requirements: 10.1, 11.1, 11.2_

  - [ ] 11.2 Add Compact Object Headers to all remaining Dockerfiles
    - Update Dockerfile_00_initial, 01_original, 02_multistage, 03_otel, 07_AOT
    - Add `-XX:+UseCompactObjectHeaders` to all ENTRYPOINT/CMD
    - _Requirements: 10.1_

- [ ] 12. Documentation and Comments
  - [ ] 12.1 Add Java 25 feature comments throughout codebase
    - Add comments explaining Scoped Values in RequestContext and filter
    - Add comments explaining Flexible Constructor Bodies in Unicorn
    - Add comments explaining Pattern Matching in UnicornService
    - Add comments explaining Unnamed Variables where used
    - Add comments explaining Sequenced Collections where used
    - _Requirements: 18.1_

  - [ ] 12.2 Add Dockerfile optimization comments
    - Add comments explaining each optimization technique
    - Document memory/startup improvements expected
    - _Requirements: 18.4_

- [ ] 13. Final Checkpoint
  - Ensure all tests pass (unit and property)
  - Verify all Dockerfiles build successfully
  - Verify application starts with each Dockerfile
  - Ask the user if questions arise

- [ ] 14. Add jqwik dependency for property testing
  - [ ] 14.1 Add jqwik to pom.xml
    - Add jqwik dependency version 1.9.3 with test scope
    - _Requirements: Testing Strategy_

## Notes

- All tasks are required for comprehensive modernization
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (100 iterations each)
- Unit tests validate specific examples and edge cases
- Dockerfile changes should be tested on both ARM64 and x64 if possible
