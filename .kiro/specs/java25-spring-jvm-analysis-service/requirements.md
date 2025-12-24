# Requirements Document

## Introduction

Modernize the existing `jvm-analysis-service` application to Java 25, Spring Boot 4, and Spring AI. The new service is named `jvm-ai-analyzer` to emphasize AI-powered analysis. The service analyzes JVM performance data (thread dumps, profiling/flamegraphs) using AI-powered recommendations via Amazon Bedrock. This modernization aligns with the patterns established in `unicorn-store-spring` Java 25 implementation, showcasing best practices for Java on AWS with container optimization.

## Glossary

- **JVM_AI_Analyzer**: The Spring Boot application that processes performance alerts and generates AI-powered analysis reports (folder: `jvm-ai-analyzer`)
- **Alert_Webhook**: REST endpoint receiving Prometheus/AlertManager webhook payloads with pod performance alerts
- **Thread_Dump**: JVM thread state snapshot retrieved from target pod's actuator endpoint
- **Profiling_Data**: Flamegraph HTML data stored in S3 from async-profiler
- **AiAnalysisService**: Service using Spring AI with Amazon Bedrock to analyze performance data
- **S3Repository**: Repository handling S3 operations for profiling data retrieval and results storage
- **Analysis_Report**: Markdown report containing AI-generated performance insights and recommendations

## Requirements

### Requirement 1: Java 25 and Spring Boot 4 Migration

**User Story:** As a developer, I want the service to run on Java 25 with Spring Boot 4, so that I can leverage the latest language features and framework improvements.

#### Acceptance Criteria

1. THE JVM_Analysis_Service SHALL use Java 25 as the compilation target
2. THE JVM_Analysis_Service SHALL use Spring Boot 4.0.0 as the parent POM
3. THE JVM_Analysis_Service SHALL use AWS SDK BOM 2.40.15 for dependency management
4. WHEN building the application, THE JVM_Analysis_Service SHALL compile without errors using Maven

### Requirement 2: Spring AI Integration with Amazon Bedrock

**User Story:** As a developer, I want to use Spring AI instead of raw AWS SDK Bedrock calls, so that I have a cleaner abstraction and better testability.

#### Acceptance Criteria

1. THE AI_Analyzer SHALL use Spring AI's ChatClient for Bedrock interactions
2. THE AI_Analyzer SHALL use Claude Sonnet 4 model (anthropic.claude-sonnet-4-20250514-v1:0) by default
3. WHEN analyzing performance data, THE AI_Analyzer SHALL send thread dump and profiling data as context
4. WHEN AI analysis fails, THE AI_Analyzer SHALL return a fallback report with error details
5. THE AI_Analyzer SHALL be configurable via Spring properties for model ID and max tokens

### Requirement 3: Java 25 Language Features

**User Story:** As a developer, I want the codebase to showcase Java 25 features, so that it serves as a reference implementation for modern Java on AWS.

#### Acceptance Criteria

1. THE JVM_Analysis_Service SHALL use Records for immutable data transfer objects (Alert, Labels, AnalysisResult)
2. THE JVM_Analysis_Service SHALL use Unnamed Variables (JEP 456) where variable values are unused
3. THE JVM_Analysis_Service SHALL use Pattern Matching for instanceof where applicable
4. THE JVM_Analysis_Service SHALL use Sequenced Collections API where applicable
5. THE JVM_Analysis_Service SHALL use Text Blocks for multi-line strings (prompts, templates)

### Requirement 4: Alert Webhook Processing

**User Story:** As an operations engineer, I want to send Prometheus alerts to the service, so that it automatically analyzes JVM performance issues.

#### Acceptance Criteria

1. WHEN a POST request is received at /webhook, THE Alert_Webhook SHALL parse the AlertManager payload
2. WHEN alerts contain valid pod and instance labels, THE JVM_Analysis_Service SHALL process each alert
3. WHEN alerts are missing required labels (pod, instance), THE JVM_Analysis_Service SHALL skip invalid alerts
4. WHEN no alerts are provided, THE Alert_Webhook SHALL return a response with count 0
5. THE Alert_Webhook SHALL return a JSON response with message and processed count

### Requirement 5: Thread Dump Retrieval

**User Story:** As an operations engineer, I want the service to retrieve thread dumps from target pods, so that thread state can be analyzed.

#### Acceptance Criteria

1. WHEN processing an alert, THE JVM_Analysis_Service SHALL retrieve thread dump from pod's actuator endpoint
2. THE JVM_Analysis_Service SHALL use configurable URL template for thread dump endpoint
3. WHEN thread dump retrieval fails, THE JVM_Analysis_Service SHALL use retry with exponential backoff
4. WHEN all retries fail, THE JVM_Analysis_Service SHALL use fallback error message

### Requirement 6: S3 Integration for Profiling Data

**User Story:** As an operations engineer, I want the service to retrieve profiling data from S3 and store analysis results, so that performance data is persisted.

#### Acceptance Criteria

1. WHEN processing an alert, THE S3_Connector SHALL retrieve latest profiling data for the pod from S3
2. THE S3_Connector SHALL store thread dump, flamegraph, and analysis report in S3
3. THE S3_Connector SHALL use configurable bucket name and prefixes via Spring properties
4. WHEN S3 operations fail, THE S3_Connector SHALL log errors and continue processing

### Requirement 7: Container-Optimized Configuration

**User Story:** As a platform engineer, I want the service optimized for container deployment on EKS/ECS, so that it runs efficiently in Kubernetes.

#### Acceptance Criteria

1. THE JVM_Analysis_Service SHALL enable Virtual Threads for improved scalability
2. THE JVM_Analysis_Service SHALL expose health endpoints for Kubernetes probes (/actuator/health)
3. THE JVM_Analysis_Service SHALL support graceful shutdown for container orchestration
4. THE JVM_Analysis_Service SHALL use YAML configuration format consistent with unicorn-store-spring
5. THE JVM_Analysis_Service SHALL disable JMX to reduce memory footprint

### Requirement 8: Testing with Testcontainers

**User Story:** As a developer, I want comprehensive tests using Testcontainers, so that I can verify S3 integration works correctly.

#### Acceptance Criteria

1. THE JVM_Analysis_Service SHALL use Testcontainers 2.0.3 for integration tests
2. THE JVM_Analysis_Service SHALL use LocalStack container for S3 testing
3. THE JVM_Analysis_Service SHALL include property-based tests using jqwik for validation logic
4. WHEN Docker is unavailable, THE test infrastructure SHALL fall back gracefully

### Requirement 9: Build and Deployment

**User Story:** As a DevOps engineer, I want consistent build configuration, so that the service can be built and deployed like unicorn-store-spring.

#### Acceptance Criteria

1. THE JVM_Analysis_Service SHALL include Jib plugin for container image building
2. THE JVM_Analysis_Service SHALL use amazoncorretto:25-al2023 as base image
3. THE JVM_Analysis_Service SHALL include native profile for GraalVM native image builds
4. THE JVM_Analysis_Service SHALL be buildable via CI workflow alongside unicorn-store-spring
