# Requirements Document

## Introduction

This document specifies the requirements for creating a new AWS workshop infrastructure system using a unified, convention-based approach. The new system will provide a single CDK codebase with convention-based conditional deployment to manage multiple workshop types efficiently.

## Glossary

- **Workshop_Infrastructure_System**: The complete infrastructure management system for AWS workshops including CDK code, CloudFormation templates, and setup scripts
- **CDK_Stack**: AWS Cloud Development Kit stack that defines infrastructure as code
- **Convention_Based_Deployment**: Deployment approach where stack name determines which resources are created
- **Workshop_Type**: Identifier that determines which resources and configurations are deployed (ide, java-on-aws, java-on-eks, java-ai-agents, java-spring-ai-agents, etc), with ide as the default containing only VPC and IDE
- **CloudFormation_Template**: AWS infrastructure definition file in YAML format
- **Setup_Script**: Shell script that configures workshop environment after infrastructure deployment
- **CodeBuild_Resource**: AWS service that executes workshop setup scripts in the cloud
- **Migration_Process**: The systematic transition from the current infrastructure/ directory to the new infra/ directory

## Requirements

### Requirement 1

**User Story:** As a workshop developer, I want a unified CDK codebase that generates different CloudFormation templates based on workshop type, so that I can eliminate code duplication and reduce maintenance overhead.

#### Acceptance Criteria

1. WHEN the Workshop_Infrastructure_System builds templates, THE system SHALL use a single CDK codebase with convention-based logic
2. WHEN a workshop type is specified via environment variable, THE CDK_Stack SHALL conditionally create resources based on that workshop type, defaulting to ide with only VPC and IDE resources
3. WHEN generating CloudFormation templates, THE system SHALL produce separate templates for each workshop type from the same codebase

### Requirement 2

**User Story:** As a workshop developer, I want infrastructure deployment to be as parallel as possible, so that overall deployment time is minimized through concurrent resource creation and setup.

#### Acceptance Criteria

1. WHEN infrastructure deployment begins, THE Workshop_Infrastructure_System SHALL deploy core resources in parallel to minimize total deployment time
2. WHEN VPC is ready, THE CodeBuild_Resource SHALL start in the workshop VPC and wait for required resources before executing setup scripts
3. WHEN setup scripts execute, THE system SHALL provide real-time progress feedback with emoji-based status messages
4. WHEN setup encounters errors, THE system SHALL display clear error messages with troubleshooting guidance

### Requirement 3

**User Story:** As a workshop developer, I want organized, reusable setup scripts with consistent error handling, so that I can maintain and debug workshop environments efficiently.

#### Acceptance Criteria

1. WHEN setup scripts execute, THE system SHALL use convention-based script discovery where script name matches stack name
2. WHEN any setup script encounters an error, THE system SHALL halt execution and display detailed error information
3. WHEN setup scripts run, THE system SHALL provide consistent emoji-based logging for visual feedback
4. WHEN setup operations timeout, THE system SHALL abort with clear timeout messages and suggested actions
5. WHEN setup scripts complete, THE system SHALL verify all critical services are operational
6. WHEN CodeBuild setup scripts fail, THE system SHALL capture full logs and provide build ID for support reference
7. WHEN critical resources are not ready, THE system SHALL wait with progress indicators up to defined timeout limits

### Requirement 4

**User Story:** As a workshop developer, I want automated template generation and distribution, so that workshop repositories always have the latest infrastructure definitions without manual synchronization.

#### Acceptance Criteria

1. WHEN the build process executes, THE system SHALL generate all workshop-specific CloudFormation templates automatically
2. WHEN templates are generated, THE system SHALL copy them to workshop directories with matching names in the same parent directory as the infrastructure repository
3. WHEN CDK code changes, THE system SHALL regenerate all affected templates through npm scripts
4. WHEN template generation fails, THE system SHALL halt the build process and report specific errors
5. WHEN templates are distributed, THE system SHALL verify successful copying to all target locations

### Requirement 5

**User Story:** As a workshop developer, I want to migrate from the current infrastructure/ directory to a new infra/ directory through incremental steps with testing at each stage, so that I can implement improvements while maintaining service continuity and validating each component.

#### Acceptance Criteria

1. WHEN the Migration_Process begins, THE system SHALL create the new infra/ directory structure without modifying infrastructure/
2. WHEN creating the base CDK stack, THE system SHALL implement ide with VPC, IDE, and CodeBuild as the foundational building blocks
3. WHEN the base stack is complete, THE system SHALL generate CloudFormation templates and validate deployment before proceeding
4. WHEN adding workshop-specific functionality, THE system SHALL migrate one workshop type at a time starting with java-on-aws
5. WHEN each workshop migration completes, THE system SHALL validate that new templates produce equivalent infrastructure to existing ones before migrating the next workshop type
6. WHEN migrating CDK constructs, THE system SHALL refactor existing code to use unified patterns and updated package names
7. WHEN migrating setup scripts, THE system SHALL reorganize them into logical categories with improved error handling
8. WHEN migrating Lambda functions, THE system SHALL create modular Python Lambda functions with inline source code stored in CDK resources for CloudFormation template compatibility
9. WHEN the new system is ready, THE system SHALL enable parallel operation where both old and new systems function independently

