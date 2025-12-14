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
- **Bootstrap_Script**: Modular shell script system that configures IDE and development environments with proper error handling and CloudFormation integration
- **Database_Naming**: Universal naming convention for database resources using "workshop-" prefix instead of workshop-specific names
- **WaitCondition**: CloudFormation resource that waits for bootstrap completion signals before allowing dependent resources to be created
- **Permission_Model**: Architecture pattern where system operations run as root and user-specific operations use sudo -u ec2-user for clean separation of concerns
- **Renovate**: Automated dependency management tool that monitors version definitions in scripts and creates pull requests for updates
- **Version_Centralization**: Pattern where all tool versions are defined at the top of scripts for easy maintenance and automated detection
- **Retry_Logic**: Network resilience pattern using exponential backoff and configurable attempts for handling transient failures
- **Modular_Scripts**: Architecture where bootstrap functionality is separated into focused scripts (UserData → bootstrap → vscode → base)

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

### Requirement 6

**User Story:** As a workshop developer, I want robust IDE bootstrap infrastructure with proper error handling and CloudFormation integration, so that workshop deployments fail fast when issues occur and provide reliable development environments.

#### Acceptance Criteria

1. WHEN IDE bootstrap scripts execute, THE system SHALL use a clean permission model where system operations run as root and user operations use sudo -u ec2-user
2. WHEN bootstrap encounters any error, THE system SHALL immediately signal CloudFormation failure to prevent partial deployments
3. WHEN fetching IDE passwords, THE system SHALL retrieve them securely from AWS Secrets Manager using IAM roles rather than CloudFormation parameters
4. WHEN installing development tools, THE system SHALL use automated dependency management with Renovate to keep versions current
5. WHEN CloudFront distributions deploy, THE system SHALL allow parallel deployment with bootstrap scripts to minimize total deployment time
6. WHEN bootstrap scripts fail, THE system SHALL provide detailed error messages with line numbers for debugging
7. WHEN VS Code and development tools install, THE system SHALL use retry logic with exponential backoff for network operations
8. WHEN the IDE is ready, THE system SHALL only expose outputs and URLs if the complete bootstrap process succeeds

### Requirement 7

**User Story:** As a workshop developer, I want comprehensive development environment setup with automated version management and modular script architecture, so that workshop participants have access to current tools and maintainers can easily update dependencies.

#### Acceptance Criteria

1. WHEN development tools install, THE system SHALL provide multiple Java versions (8, 17, 21, 25) with configurable default version
2. WHEN Node.js installs, THE system SHALL use LTS version 20 via NVM for stability and compatibility
3. WHEN Kubernetes tools install, THE system SHALL include kubectl, Helm, eks-node-viewer, k9s, and e1s for comprehensive cluster management
4. WHEN container tools install, THE system SHALL include Docker and SOCI snapshotter for optimized container operations
5. WHEN version definitions change, THE system SHALL centralize all versions at the top of scripts for easy Renovate detection
6. WHEN unused tools are identified, THE system SHALL comment them out while maintaining Renovate configuration for future use
7. WHEN script organization improves, THE system SHALL maintain clear separation between system setup, VS Code configuration, and development tools installation

### Requirement 8

**User Story:** As a workshop participant, I want a clean VS Code environment without AI agent panels or distractions, so that I can focus on workshop content without being prompted by AI features.

#### Acceptance Criteria

1. WHEN VS Code Server 4.106.3 starts, THE system SHALL disable the Agent Sessions view to prevent "Build with Agent" panel from appearing
2. WHEN VS Code loads, THE system SHALL disable GitHub Copilot features to prevent AI code suggestions and chat interfaces
3. WHEN VS Code initializes, THE system SHALL disable chat extension unification to prevent consolidated AI chat views
4. WHEN workshop participants use the IDE, THE system SHALL provide a distraction-free coding environment focused on workshop learning objectives

### Requirement 9

**User Story:** As a workshop developer, I want consistent and informative bootstrap logging with actual version numbers, so that I can easily debug deployment issues and verify tool installations.

#### Acceptance Criteria

1. WHEN tools install successfully, THE system SHALL display messages in format "✅ Success: [Tool Name] [Version]" with actual installed versions
2. WHEN version detection is available, THE system SHALL capture and display real version numbers (e.g., "npm 10.9.0", "CDK 2.167.1")
3. WHEN tools don't provide version information, THE system SHALL show tool name without redundant suffixes like "download" or "latest"
4. WHEN bootstrap scripts execute, THE system SHALL maintain consistent logging format across all scripts (bootstrap, vscode, base)
5. WHEN installation completes, THE system SHALL eliminate redundant verification messages and duplicate version logging

### Requirement 10

**User Story:** As a workshop developer, I want bulletproof CloudFormation signaling that handles all failure scenarios, so that deployments never hang and always provide immediate feedback on success or failure.

#### Acceptance Criteria

1. WHEN UserData script encounters errors, THE system SHALL trap failures and signal CloudFormation immediately with error status
2. WHEN repository cloning fails, THE system SHALL signal CloudFormation failure and exit with clear error message
3. WHEN bootstrap script fails to execute, THE system SHALL provide fallback signaling from UserData to prevent hanging deployments
4. WHEN bootstrap script runs successfully, THE system SHALL handle internal signaling through error traps and final success signal
5. WHEN any component fails, THE system SHALL ensure CloudFormation receives failure signal within seconds rather than timing out after 30 minutes

### Requirement 11

**User Story:** As a workshop developer, I want reliable and maintainable UserData template generation, so that I can modify infrastructure scripts without breaking deployments due to parameter misalignment errors.

#### Acceptance Criteria

1. WHEN UserData templates are generated, THE system SHALL use named template variables instead of positional String.format placeholders
2. WHEN template variables are replaced, THE system SHALL use individual replacement calls for each variable to eliminate counting errors
3. WHEN new variables are added to UserData, THE system SHALL not require manual parameter counting or alignment
4. WHEN CloudFormation templates are generated, THE system SHALL verify all template variables are properly substituted with no unreplaced placeholders
5. WHEN UserData scripts are modified, THE system SHALL maintain self-documenting code where variable replacements are explicit and clear

### Requirement 12

**User Story:** As a workshop developer, I want universal database naming conventions, so that database resources can be reused across different workshop types without workshop-specific identifiers.

#### Acceptance Criteria

1. WHEN database resources are created, THE system SHALL use "workshop-" prefix instead of workshop-specific names like "unicornstore-"
2. WHEN database cluster is created, THE system SHALL name it "workshop-db-cluster" for universal identification
3. WHEN database instance is created, THE system SHALL name it "workshop-db-writer" for consistent naming
4. WHEN database secrets are created, THE system SHALL use names "workshop-db-secret" and "workshop-db-password-secret"
5. WHEN database parameters are stored, THE system SHALL use "workshop-db-connection-string" in Parameter Store
6. WHEN database name is specified, THE system SHALL use "workshop" as the database name instead of workshop-specific names

### Requirement 13

**User Story:** As a workshop developer, I want a standardized EKS cluster with universal naming and modern configuration using the latest CDK constructs, so that Kubernetes-based workshops have consistent infrastructure with current best practices and native CloudFormation resources.

#### Acceptance Criteria

1. WHEN EKS cluster is created, THE system SHALL use the EKS v2 developer preview construct from package "software.amazon.awscdk.services.eks.v2.alpha" for native CloudFormation resource support
2. WHEN EKS cluster is created, THE system SHALL name it "workshop-cluster" for universal identification across workshop types
3. WHEN EKS cluster is configured, THE system SHALL use version 1.34 for current Kubernetes features and security updates
4. WHEN EKS cluster deploys, THE system SHALL enable Auto Mode with "system" and "general-purpose" node pools for automatic node management
5. WHEN EKS cluster networking is configured, THE system SHALL place cluster in private subnets with public and private API access for security and flexibility
6. WHEN EKS cluster logging is enabled, THE system SHALL activate all log types (api, audit, authenticator, controllerManager, scheduler) for comprehensive monitoring
7. WHEN EKS cluster permissions are configured, THE system SHALL use Access Entries authentication mode instead of deprecated ConfigMap-based authentication
8. WHEN EKS cluster access is configured, THE system SHALL create Access Entry for WSParticipantRole and IDE instance role with cluster admin permissions for workshop participant access

### Requirement 14

**User Story:** As a workshop developer, I want database secrets mounted as environment variables in Kubernetes pods using the AWS Secrets Store CSI Driver, so that applications can securely access database credentials without hardcoding them and without requiring External Secrets Operator.

#### Acceptance Criteria

1. WHEN EKS cluster is configured for secrets management, THE system SHALL use AWS Secrets Store CSI Driver add-on instead of External Secrets Operator for mounting secrets
2. WHEN database secrets are mounted, THE system SHALL mount "workshop-db-secret" as environment variables in pods for database connection credentials
3. WHEN database password is mounted, THE system SHALL mount "workshop-db-password-secret" as environment variables in pods for database authentication
4. WHEN database connection string is mounted, THE system SHALL mount "workshop-db-connection-string" from Parameter Store as environment variables in pods for application configuration
5. WHEN secrets access is configured, THE system SHALL use EKS Pod Identity with AWSSecretsManagerClientReadOnlyAccess managed policy for secure secrets retrieval
6. WHEN SecretProviderClass is created, THE system SHALL define which secrets and parameters to mount as files and expose as environment variables in Kubernetes workloads

### Requirement 15

**User Story:** As a workshop developer, I want essential EKS add-ons and configurations for workshop functionality, so that participants have access to storage, ingress, S3 mounting, and proper workshop permissions without manual setup.

#### Acceptance Criteria

1. WHEN EKS cluster is configured for storage, THE system SHALL create GP3 StorageClass as default with encryption enabled for persistent volume claims since EKS Auto Mode does not provide encrypted GP3 by default
2. WHEN EKS cluster is configured for ingress, THE system SHALL create ALB IngressClass and IngressClassParams resources for Application Load Balancer integration since EKS Auto Mode requires explicit IngressClass configuration
3. WHEN EKS cluster is configured for secrets management, THE system SHALL install AWS Secrets Store CSI Driver add-on for mounting database secrets as environment variables
4. WHEN EKS cluster is configured for S3 access, THE system SHALL install AWS Mountpoint S3 CSI driver add-on for S3 bucket mounting capabilities
5. WHEN EKS cluster is configured for authentication, THE system SHALL install EKS Pod Identity Agent add-on for modern IAM authentication with AWS services
6. WHEN EKS cluster is configured for workshop access, THE system SHALL grant WSParticipantRole cluster admin permissions via Access Entries for workshop participant access
7. WHEN EKS cluster setup is complete, THE system SHALL verify all three add-ons (Secrets Store CSI Driver, Mountpoint S3 CSI Driver, Pod Identity Agent) are installed and functional before marking deployment as successful

### Requirement 16

**User Story:** As a workshop developer, I want a complete EKS add-on based architecture that eliminates Helm chart dependencies, so that the infrastructure uses only AWS-native managed services for simplified operations and maintenance.

#### Acceptance Criteria

1. WHEN EKS infrastructure is deployed, THE system SHALL use only EKS add-ons and eliminate all Helm chart installations for a fully AWS-native setup
2. WHEN comparing to original infrastructure, THE system SHALL reduce Helm charts from 2 to 0 by converting External Secrets Operator and Mountpoint S3 CSI Driver to EKS add-ons
3. WHEN EKS add-ons are installed, THE system SHALL configure AWS Secrets Store CSI Driver add-on to replace External Secrets Operator functionality
4. WHEN EKS add-ons are installed, THE system SHALL configure AWS Mountpoint S3 CSI Driver add-on to replace Helm chart installation
5. WHEN EKS add-ons are installed, THE system SHALL configure EKS Pod Identity Agent add-on to provide modern IAM authentication for other add-ons
6. WHEN add-on architecture is complete, THE system SHALL provide equivalent functionality to original setup while using only AWS-managed components

### Requirement 17

**User Story:** As a workshop developer, I want a complete workshop orchestration system that executes foundational and workshop-specific setup in sequence, so that participants have a fully configured development environment with all necessary tools and services.

#### Acceptance Criteria

1. WHEN java-on-aws workshop setup executes, THE system SHALL first run base.sh for foundational development tools installation
2. WHEN base setup completes successfully, THE system SHALL proceed to EKS-specific implementation including cluster configuration and add-ons
3. WHEN workshop orchestration encounters errors, THE system SHALL halt execution and provide clear error messages indicating which phase failed
4. WHEN all setup phases complete, THE system SHALL verify that both base tools and EKS services are operational
5. WHEN workshop script executes, THE system SHALL provide progress feedback for each major phase (base setup, EKS setup, verification)

### Requirement 18

**User Story:** As a workshop developer, I want EKS cluster setup scripts that wait for cluster readiness and configure kubectl context, so that subsequent operations can reliably interact with the cluster and participants have proper access.

#### Acceptance Criteria

1. WHEN EKS setup script executes, THE system SHALL check cluster status and wait until kubectl get ns command works successfully
2. WHEN cluster is ready, THE system SHALL update kubeconfig and add cluster to kubectl context
3. WHEN kubectl context is configured, THE system SHALL deploy GP3 StorageClass, ALB IngressClass, and SecretProviderClass resources
4. WHEN setup script completes, THE system SHALL verify all deployed resources are functional
5. WHEN base development tools are installed, THE system SHALL include kubectl alias 'k' for convenience

### Requirement 19

**User Story:** As a workshop developer, I want EKS cluster and database to deploy in parallel for optimal deployment time, so that infrastructure provisioning is as fast as possible.

#### Acceptance Criteria

1. WHEN EKS cluster is created, THE system SHALL depend only on VPC and deploy in parallel with other resources
2. WHEN database is created, THE system SHALL depend only on VPC and deploy in parallel with EKS cluster
3. WHEN both EKS and database are deploying, THE system SHALL not create unnecessary dependencies between them
4. WHEN parallel deployment completes, THE system SHALL ensure both resources are available for workshop setup scripts

