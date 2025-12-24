# Implementation Plan: JVM Analysis Service Java 25 Modernization

## Overview

Modernize jvm-analysis-service to Java 25, Spring Boot 4, and Spring AI. Create new implementation at `apps/java25/jvm-ai-analyzer/` following patterns from `apps/java25/unicorn-store-spring/`. The service is renamed to `jvm-ai-analyzer` to emphasize AI-powered analysis, with Spring-conventional class names (Services end with `Service`, data access = `Repository`).

## Tasks

- [x] 1. Project Setup and Build Configuration
  - [x] 1.1 Create project structure at `apps/java25/jvm-ai-analyzer/`
    - Create directory structure: `src/main/java/com/unicorn/jvm/`, `src/main/resources/`, `src/test/java/`
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 1.2 Create pom.xml with Java 25, Spring Boot 4, Spring AI dependencies
    - Parent: spring-boot-starter-parent 4.0.0
    - Java version: 25
    - Dependencies: spring-boot-starter-web, spring-ai-bedrock, aws-sdk-s3, resilience4j, testcontainers 2.0.3, jqwik
    - Profiles: jvm (Jib), native (GraalVM)
    - _Requirements: 1.1, 1.2, 1.3, 9.1, 9.2, 9.3_
  - [x] 1.3 Create application.yaml with container-optimized configuration
    - Virtual threads enabled
    - JMX disabled
    - Health probes configured
    - Graceful shutdown
    - Spring AI Bedrock configuration
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 2.2, 2.5_

- [x] 2. Data Models (Java Records)
  - [x] 2.1 Create AlertWebhookRequest record with nested Alert and Labels records
    - Implement podIp() derived method in Labels
    - Use @JsonProperty annotations for JSON mapping
    - _Requirements: 3.1, 4.1_
  - [x] 2.2 Create AnalysisResult record for webhook response
    - Fields: message (String), count (int)
    - _Requirements: 3.1, 4.5_
  - [x] 2.3 Write property test for alert validation logic
    - **Property 1: Alert Validation Consistency**
    - **Validates: Requirements 4.2, 4.3**

- [x] 3. Core Service Components
  - [x] 3.1 Create JvmAnalysisApplication main class
    - @SpringBootApplication annotation
    - S3Client bean configuration
    - _Requirements: 1.4_
  - [x] 3.2 Create JvmAnalysisController with webhook endpoint
    - POST /webhook endpoint
    - Alert validation using pattern matching
    - Return AnalysisResult record
    - Use unnamed variables for ignored exceptions
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 3.2, 3.3_
  - [x] 3.3 Write property test for webhook response structure
    - **Property 4: Webhook Response Structure**
    - **Validates: Requirements 4.5**

- [x] 4. AI Analysis Component (Spring AI)
  - [x] 4.1 Create AiAnalyzer component using Spring AI ChatClient
    - Inject ChatClient.Builder
    - Build analysis prompt with text blocks
    - Implement fallback report on error
    - _Requirements: 2.1, 2.3, 2.4, 3.5_
  - [x] 4.2 Write property test for AI prompt content
    - **Property 2: AI Analysis Contains Input Context**
    - **Validates: Requirements 2.3**
  - [x] 4.3 Write property test for AI fallback behavior
    - **Property 3: AI Fallback on Error**
    - **Validates: Requirements 2.4**

- [x] 5. S3 Integration
  - [x] 5.1 Create S3Connector component
    - getLatestProfilingData() - retrieve from S3
    - storeResults() - store thread dump, profiling, analysis
    - Use Sequenced Collections where applicable
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 3.4_
  - [x] 5.2 Write property test for S3 storage completeness
    - **Property 5: S3 Storage Completeness**
    - **Validates: Requirements 6.2**

- [x] 6. Service Orchestration
  - [x] 6.1 Create JvmAnalysisService to orchestrate workflow
    - Process alerts sequentially
    - Retrieve thread dump with retry
    - Get profiling data from S3
    - Analyze with AI
    - Store results
    - Use unnamed variables for caught exceptions
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 3.2_

- [x] 7. Checkpoint - Core Implementation
  - Ensure application compiles and starts
  - Verify all components are wired correctly
  - Ask the user if questions arise

- [x] 8. Test Infrastructure
  - [x] 8.1 Create TestInfrastructureInitializer with LocalStack
    - Start LocalStack container for S3
    - Configure AWS credentials for tests
    - Implement Docker unavailable fallback
    - _Requirements: 8.1, 8.2, 8.4_
  - [x] 8.2 Create integration test for S3Connector
    - Test getLatestProfilingData with LocalStack
    - Test storeResults with LocalStack
    - _Requirements: 8.2_
  - [x] 8.3 Create integration test for webhook endpoint
    - Test valid alert processing
    - Test invalid alert filtering
    - Test empty alerts response
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [x] 9. Final Checkpoint
  - Ensure all tests pass
  - Verify property tests run with 100 iterations
  - Ask the user if questions arise

- [x] 10. CI Integration
  - [x] 10.1 Update CI workflow to build jvm-analysis-service
    - Add build step in build-java25 job
    - _Requirements: 9.4_

## Notes

- All property-based tests are required
- Each property test validates specific correctness properties from the design
- Integration tests use Testcontainers 2.0.3 with LocalStack for S3
- Follow patterns from unicorn-store-spring for consistency
