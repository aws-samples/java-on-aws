# Implementation Plan: Java 25 + Spring Boot 4 Modernization

## Overview

This implementation plan transforms unicorn-store-spring-java25 into a showcase workshop application demonstrating Java 25, Spring Framework 7, and Spring Boot 4 best practices. Tasks are organized by priority: critical fixes first, then Java features, tests, and finally Dockerfiles.

## Tasks

- [x] 1. Critical Fixes and Dependency Updates
  - [x] 1.1 Update AWS SDK to version 2.40.14+
  - [x] 1.2 Remove --add-opens JVM flags from surefire plugin
  - [x] 1.3 Remove unused AWS SDK dependencies

- [x] 2. Java 25 Scoped Values Implementation
  - [x] 2.1 Create RequestContext class with ScopedValue
  - [x] 2.2 Create RequestContextFilter with ScopedValue.where().run() pattern
  - [x] 2.3 Update UnicornService to use Scoped Values
  - [x] 2.4 Write property test for Request ID uniqueness

- [x] 3. Java 25 Flexible Constructor Bodies
  - [x] 3.1 Update Unicorn constructor with pre-super validation (JEP 513)
  - [x] 3.2 Remove duplicate record-style accessors from Unicorn
  - [x] 3.3 Add equals/hashCode to Unicorn entity
  - [x] 3.4 Write property test for constructor validation (UnicornValidationPropertyTest)
  - [x] 3.5 Write property test for equals/hashCode contract (UnicornEqualsPropertyTest)

- [x] 4. Modern Java Language Features
  - [x] 4.1 Add unnamed variables to catch blocks (Java 22)
  - [x] 4.2 Add Sequenced Collections usage (getFirst/getLast)
  - [x] 4.3 Verify text blocks usage (already present in UnicornController)

- [x] 5. Checkpoint - Core Java Features
  - All tests pass (26 tests)
  - Application compiles correctly

- [x] 6. Test Infrastructure Simplification and Testcontainers 2.0 Migration
  - [x] 6.1 Update pom.xml for Testcontainers 2.0.3 (new artifact coordinates)
  - [x] 6.2 Create TestInfrastructure annotation
  - [x] 6.3 Create TestInfrastructureInitializer for Testcontainers 2.0
  - [x] 6.4 Delete redundant test infrastructure files (6 files deleted)
  - [x] 6.5 Update UnicornControllerTest with @TestInfrastructure and AssertJ
  - [x] 6.6 Fix H2 fallback schema (RANDOM_UUID)
  - [ ] 6.7 Write property test for JSON serialization (optional)

- [x] 7. EventBridge Integration Testing
  - [x] 7.1 Verify UnicornPublisher uses EventBridge correctly
  - [x] 7.2 Update error handling for event publishing failures
  - [ ] 7.3 Write property test for event publishing (optional)
  - [ ] 7.4 Write property test for graceful degradation (optional)

- [x] 8. Checkpoint - Tests Complete
  - All 26 tests pass (3 property test classes + 2 integration tests)

- [x] 9. Dockerfile Improvements - Base Image Standardization
  - [x] 9.1 Standardize all Dockerfiles to use al2023 runner image
  - [x] 9.2 Update Jib plugin to use al2023 base image
  - [x] 9.3 Verify CRaC and GraalVM exceptions are documented

- [x] 10. Dockerfile Improvements - Size Optimization
  - [x] 10.1 Fix Dockerfile_04_optimized_JVM (--compress zip-6, -XX:+UseCompactObjectHeaders)
  - [x] 10.2 Rename and fix Dockerfile_05_GraalVM → Dockerfile_05_native
  - [x] 10.3 Fix Dockerfile_06_SOCI

- [x] 11. Dockerfile Improvements - Startup Optimization
  - [x] 11.1 Update Dockerfile_08_CDS
  - [x] 11.2 Update Dockerfile_09_CRaC

- [x] 12. Dockerfile Improvements - Observability
  - [x] 12.1 Verify Dockerfile_10_async_profiler multi-arch support
  - [x] 12.2 Add Compact Object Headers to all remaining Dockerfiles

- [x] 13. Documentation and Comments - Standardize All Comments
  - [x] 13.1 RequestContext.java - Reduce 25-line Javadoc to 2-line comment + JEP link
  - [x] 13.2 RequestContextFilter.java - Reduce 12-line Javadoc to 1-line comment
  - [x] 13.3 Unicorn.java - Remove verbose Javadocs, keep only inline comment
  - [x] 13.4 UnicornService.java - Reduce method Javadocs to inline comments
  - [x] 13.5 TestInfrastructure.java - Reduce to 1-line comment
  - [x] 13.6 TestInfrastructureInitializer.java - Reduce to 2-line comment
  - [x] 13.7 RequestContextPropertyTest.java - Reduce verbose Javadocs to 1-line
  - [x] 13.8 Dockerfile optimization comments (already done)

- [x] 13. Final Checkpoint
  - [x] All tests pass
  - [x] All Dockerfiles standardized

- [x] 14. Add jqwik dependency for property testing
  - [x] 14.1 Add jqwik 1.9.3 to pom.xml

- [x] 15. Add Code Formatting with Spotless
  - [x] 15.1 Add Spotless Maven plugin to pom.xml (commented - Java 25 compatibility issue)
  - [x] 15.2 Add EditorConfig for IDE consistency
  - [ ] 15.3 Run Spotless to format all code (blocked by Java 25 compatibility)

- [x] 16. Clean Up pom.xml with sortpom
  - [x] 16.1 Add sortpom-maven-plugin 4.0.0 to pom.xml
  - [x] 16.2 Run sortpom:sort to organize pom.xml

- [x] 17. Clean Up application.yaml
  - [x] 17.1 Reorganize application.yaml with logical sections and comments
  - [x] 17.2 Add graceful shutdown configuration

- [x] 18. Final Code Quality Review
  - [x] 18.1 Review package structure (clean separation maintained)
  - [x] 18.2 Fix blackhole variable in ThreadGeneratorService
  - [ ] 18.3 Review and clean up imports (deferred - Spotless blocked)
  - [ ] 18.4 Final polish

## Completed Summary

### Java 25 Features Implemented:
- **Scoped Values (JEP 506)**: RequestContext + RequestContextFilter with ScopedValue.where().run()
- **Flexible Constructor Bodies (JEP 513)**: Unicorn entity with pre-super validation
- **Unnamed Variables (Java 22)**: Used in catch blocks throughout codebase
- **Sequenced Collections (Java 21)**: getFirst()/getLast() in UnicornService
- **Pattern Matching (Java 21)**: Switch expressions in validateUnicorn()

### Test Infrastructure:
- Testcontainers 2.0.3 with new artifact coordinates
- Unified @TestInfrastructure annotation
- H2 fallback for environments without Docker
- 3 property test classes with jqwik 1.9.3

### Code Quality:
- sortpom for pom.xml organization
- EditorConfig for IDE consistency
- Clean application.yaml with section comments
- Volatile blackhole pattern in ThreadGeneratorService

## Notes

- Spotless plugin has compatibility issues with Java 25 (commented out in pom.xml)
- Dockerfile tasks remain for container optimization work
- All 26 tests pass successfully
