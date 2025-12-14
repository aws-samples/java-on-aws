# Implementation Plan

## Infrastructure Setup (1.x)

- [x] 1.1 Create new infra directory structure
  - Create infra/{cdk,cfn,scripts/{workshops,setup,lib,deploy,test,cleanup},policies} directories
  - Create CDK Java package structure: infra/cdk/src/main/java/sample/com/{constructs,stacks}
  - Create infra/cdk/src/main/resources directory for assets
  - Ensure infrastructure/ directory remains untouched during setup
  - _Requirements: 5.1_

- [x] 1.2 Initialize CDK project structure
  - Create infra/cdk/pom.xml with unified dependencies (CDK 2.215.0, Java 25)
  - Create infra/cdk/cdk.json with CDK configuration
  - Set up Maven project structure with proper groupId (sample.com) and artifactId (infra)
  - Configure CDK app entry point
  - _Requirements: 5.6_

- [x] 1.3 Create common script utilities
  - Create infra/scripts/lib/common.sh with emoji-based logging functions (log_info, log_success, log_error, log_warning)
  - Implement consistent error handling with handle_error function and trap setup
  - Create infra/scripts/lib/wait-for-resources.sh for resource readiness checking
  - Set executable permissions on all script files
  - _Requirements: 3.3, 3.7_

## Build System (2.x)

- [x] 2.1 Create template generation script
  - Create infra/scripts/cfn/generate.sh that builds CDK and generates workshop-template.yaml
  - Implement proper error handling and progress feedback with emoji logging
  - Include sed transformation for CloudFormation substitutions (AccountId pattern)
  - Test script execution and validate generated template structure
  - _Requirements: 4.1, 4.4_

- [x] 2.2 Create workshop sync script
  - Create infra/scripts/cfn/sync.sh that copies workshop-template.yaml to workshop directories as {workshop}-stack.yaml
  - Include iam-policy.json copying from cdk/src/main/resources/ directory to workshop static/ directories
  - Implement directory existence checking and error reporting
  - Support workshop list: ide, java-on-aws, java-on-eks, java-ai-agents, java-spring-ai-agents
  - _Requirements: 4.2, 4.5_

- [x] 2.3 Set up build automation
  - Create infra/package.json with generate and sync npm scripts
  - Make scripts executable and test npm run generate && npm run sync workflow
  - Validate that generated templates are copied to correct locations with proper naming
  - Copy existing iam-policy.json to infra/cdk/src/main/resources/ for single source of truth
  - _Requirements: 4.3_

## Base IDE Stack (10.x)

- [x] 10.1 Create core CDK constructs
  - Create infra/cdk/src/main/java/sample/com/constructs/Roles.java for IAM roles and policies
  - Create infra/cdk/src/main/java/sample/com/constructs/Vpc.java for VPC with 2 AZs and 1 NAT gateway
  - Create infra/cdk/src/main/java/sample/com/constructs/Ide.java for VS Code IDE environment
  - Create infra/cdk/src/main/java/sample/com/constructs/CodeBuild.java for workshop setup automation
  - _Requirements: 1.1, 5.6_

- [x] 10.2 Migrate and refactor Roles construct
  - Copy infrastructure/cdk/src/main/java/com/unicorn/constructs/WorkshopFunction.java patterns for IAM setup
  - Update package names from com.unicorn to sample.com
  - Consolidate all IAM roles and policies into single Roles construct
  - Include Bedrock permissions for AI workshops in the unified roles
  - _Requirements: 5.6_

- [x] 10.3 Migrate and refactor Vpc construct
  - Copy infrastructure/cdk/src/main/java/com/unicorn/constructs/WorkshopVpc.java
  - Update package names and simplify to standard VPC pattern
  - Ensure VPC supports both IDE and EKS workloads with proper subnet configuration
  - Remove workshop-specific customizations, keep generic VPC setup
  - _Requirements: 5.6_

- [x] 10.4 Create optimized Python Lambda function with direct CDK implementation
  - Create Python source file infra/cdk/src/main/resources/launcher.py for EC2 instance launching
  - Use direct Function.Builder.create() with Code.fromInline(loadFile()) approach
  - Replace prefix.py, password.py, database.py with native CDK implementations
  - Move bootstrap functionality to EC2 User Data script for simplicity
  - Maintain identical functionality while reducing Lambda complexity by 80%
  - _Requirements: 5.8_

- [x] 10.5 Migrate and refactor Ide construct
  - Copy infrastructure/cdk/src/main/java/com/unicorn/constructs/VSCodeIde.java
  - Update package names and integrate with new Roles and Vpc constructs
  - Replace existing Lambda functions with single launcher Lambda using direct CDK Function creation
  - Create comprehensive bootstrap script in infra/cdk/src/main/resources/bootstrap.sh
  - Ensure IDE construct creates proper EC2 instance with complete VS Code setup and CloudFront
  - _Requirements: 5.6_

- [x] 10.6 Migrate and refactor CodeBuild construct
  - Copy infrastructure/cdk/src/main/java/com/unicorn/constructs/CodeBuildResource.java
  - Update to use new Roles construct and accept WORKSHOP_TYPE environment variable
  - Configure CodeBuild to run in VPC and execute workshop-specific setup scripts
  - Include proper error handling and timeout configuration (60 minutes)
  - _Requirements: 5.6, 3.6_

- [x] 10.7 Create unified WorkshopStack
  - Create infra/cdk/src/main/java/sample/com/WorkshopStack.java
  - Implement environment variable logic: TEMPLATE_TYPE with "base" default
  - Always create: Vpc, Ide, CodeBuild
  - Conditionally create Roles only for non-base templates
  - _Requirements: 1.2, 1.3_

- [x] 10.8 Create CDK application entry point
  - Create infra/cdk/src/main/java/sample/com/WorkshopApp.java
  - Configure single WorkshopStack instantiation
  - Set up proper CDK app synthesis
  - Test CDK synth command produces valid CloudFormation template
  - _Requirements: 1.1_

- [x] 10.9 Create modular bootstrap scripts
  - Create infra/cdk/src/main/resources/scripts/ide-bootstrap.sh for system setup and orchestration
  - Create infra/scripts/ide/vscode.sh for complete VS Code IDE setup
  - Create infra/scripts/ide/ide.sh as placeholder for base development tools
  - Implement git branch configuration via GIT_BRANCH environment variable (defaults to main)
  - _Requirements: 3.1, 3.3_

- [x] 10.10 Refactor bootstrap script into modular components
  - Split monolithic ide-bootstrap.sh into system setup + VS Code setup + workshop orchestration
  - Define git branch in code, VS Code version uses latest by default
  - Implement modular script structure: ide-bootstrap.sh → vscode.sh → {workshop}.sh
  - Added comprehensive refactoring with helper functions and error handling
  - Standardized on dnf package manager across all scripts
  - Function-based organization with consistent logging and cleanup
  - _Requirements: 3.3, 5.7_

- [x] 10.11 Test and validate IDE stack
  - Generate CloudFormation template: npm run generate
  - Validate template contains only VPC, IDE, CodeBuild, and IAM resources
  - Test template deployment in AWS (optional, can be done manually)
  - Verify CodeBuild can find and execute ide.sh script
  - _Requirements: 5.3_

- [x] 10.12 Comprehensive script refactoring and optimization
  - Updated all tool versions to latest available (kubectl 1.34.2, Helm 3.19.3, etc.)
  - Pinned Node.js to version 20 LTS and Helm to v3.x for stability
  - Moved Docker and jq from bootstrap to ide.sh for better organization
  - Implemented comprehensive refactoring with helper functions and error handling
  - Added consistent logging, download verification, and cleanup
  - Standardized on dnf package manager and improved comments
  - Set VS Code to use latest version by default
  - _Requirements: 3.3, 5.7_

- [x] 10.13 Implement minimal UserData architecture and finalize base template
  - Created infra/cdk/src/main/resources/ec2-userdata.sh (2.4KB - 46% size reduction)
  - Moved bootstrap logic to infra/scripts/ide/bootstrap.sh (3.8KB)
  - Renamed ide.sh to base.sh for base template type
  - Updated CDK to use TEMPLATE_TYPE="base" as default
  - Simplified CodeBuild buildSpec to match original (service-linked role creation only)
  - Updated bootstrap to look for template scripts in infra/scripts/ide/${TEMPLATE_TYPE}.sh
  - Flattened UserData script path and removed workshops directory
  - _Requirements: 3.3, 5.7_

## IDE Bootstrap Improvements (11.x)

- [x] 11.1 Implement secure password management and CloudFormation integration
  - Removed IDE password from UserData parameters to eliminate CloudFormation resolution issues
  - Updated bootstrap to fetch passwords directly from AWS Secrets Manager using IAM roles
  - Added proper error handling for secret retrieval with validation and fallback
  - Configured EC2 instance IAM role with secretsmanager:GetSecretValue permissions
  - _Requirements: 6.3_

- [x] 11.2 Implement robust error handling and CloudFormation signaling
  - Added error trap in bootstrap.sh to catch failures at any line and signal CloudFormation immediately
  - Implemented proper cfn-signal integration with WaitCondition for fast failure detection
  - Added CloudFormation helper scripts installation (aws-cfn-bootstrap package)
  - Configured outputs and critical resources to depend on WaitCondition for proper failure propagation
  - _Requirements: 6.2, 6.6_

- [x] 11.3 Optimize deployment architecture for parallel execution
  - Removed CloudFront dependency on bootstrap completion to enable parallel deployment
  - Configured bootstrap to query CloudFront domain while distribution is still deploying
  - Maintained WaitCondition dependency only for user-facing outputs (URL, password)
  - Achieved faster overall deployment through infrastructure and application parallelization
  - _Requirements: 6.5_

- [x] 11.4 Implement clean permission model and fix execution context
  - Analyzed discrepancy between working /infrastructure bootstrap (root context) and new /infra bootstrap (ec2-user context)
  - Updated UserData to run bootstrap as root matching proven working pattern
  - Removed sudo prefixes from system operations (dnf, systemctl, tee /etc/)
  - Maintained sudo -u ec2-user only for user-specific operations (config files, SSH keys)
  - Fixed all permission-related failures in VS Code and Caddy installation
  - _Requirements: 6.1_

- [x] 11.5 Implement automated dependency management with Renovate
  - Updated .github/renovate.yml with comprehensive version tracking for all development tools
  - Added regex managers for NVM, Node.js, Maven, VS Code, kubectl, Helm, eks-node-viewer, SOCI, yq
  - Organized version definitions at top of all scripts for easy Renovate detection
  - Commented out unused tools (eksctl, docker-compose) while maintaining Renovate configuration
  - Enabled weekly automated dependency updates on Monday mornings
  - _Requirements: 6.4_

- [x] 11.6 Implement retry logic and network resilience
  - Added comprehensive retry functions (retry_critical, retry_optional) with configurable attempts and delays
  - Implemented exponential backoff for network operations (AWS CLI, VS Code, development tools)
  - Added proper error handling for interactive prompts (unzip conflicts, package installations)
  - Configured all network-dependent operations to use retry logic with appropriate failure modes
  - _Requirements: 6.7_

- [x] 11.7 Optimize version management and script organization
  - Moved all version definitions to top of scripts for easy Renovate detection and management
  - Updated VS Code to use environment variable passing for version consistency
  - Centralized version management for VSCODE_VERSION, NVM_VERSION, NODE_VERSION, MAVEN_VERSION, etc.
  - Commented out unused tools (DOCKER_COMPOSE_VERSION, EKSCTL_VERSION) while maintaining Renovate tracking
  - Organized scripts with clear version sections and improved maintainability
  - _Requirements: 6.4_

- [x] 11.8 Resolve CloudFormation signaling and WaitCondition issues
  - Fixed CloudFormation hanging by implementing proper error trapping and cfn-signal integration
  - Added line-level error detection with immediate CloudFormation failure signaling
  - Configured WaitCondition dependencies to ensure outputs only appear after successful bootstrap
  - Implemented proper error handling for all bootstrap phases (UserData, bootstrap, vscode, base)
  - Ensured fast failure detection (<30 seconds) vs previous 30-minute timeout
  - _Requirements: 6.2, 6.6_

- [x] 11.9 Finalize comprehensive development environment setup
  - Updated base.sh with complete development toolchain (Java 8,17,21,25, Node.js 20, Maven 3.9.11)
  - Added Kubernetes tools (kubectl 1.34.2, Helm 3.19.3, eks-node-viewer, k9s, e1s)
  - Integrated container tools (Docker, SOCI snapshotter 0.12.0) with proper configuration
  - Added AWS tools (SAM CLI, Session Manager Plugin) and utilities (jq, yq 4.49.2)
  - Added kubectl alias 'k' for convenience in base.sh
  - Implemented comprehensive error handling and logging for all tool installations
  - _Requirements: 6.4, 6.7, 18.5_

- [x] 11.10 Fix CloudFormation signaling permissions
  - Added cloudformation:SignalResource permission to IDE instance IAM role
  - Resolved AccessDenied error when bootstrap attempts to signal CloudFormation completion
  - Ensured proper CloudFormation integration with WaitCondition for fast failure detection
  - Validated bootstrap completion signaling works correctly for both success and failure cases
  - _Requirements: 6.2, 6.6_

- [x] 11.11 Improve logging consistency and reduce verbosity
  - Standardized all bootstrap and VS Code logging to use consistent timestamp format (YYYY-MM-DD HH:MM:SS)
  - Added quiet flags (-q) to dnf package manager commands to reduce log noise
  - Fixed "Error: No matching Packages to list" message by suppressing stderr in code-server check
  - Ensured consistent Lambda function naming (ide-cloudfront-prefix-lookup, ide-ec2-launcher) independent of stack name
  - Maintained base.sh existing perfect logging pattern with log_info function
  - _Requirements: 6.6_

- [x] 11.12 Fix CloudFormation WaitCondition signaling architecture
  - Fixed resource naming conflicts by using proper CDK construct names (BootstrapWaitCondition vs IdeBootstrapWaitCondition)
  - Implemented WaitConditionHandle URL approach matching original infrastructure pattern
  - Updated all cfn-signal calls to use handle URL instead of resource names (eliminates hash suffix issues)
  - Applied logical resource naming: ide- prefix for IDE resources, setup-/workshop- prefix for setup resources
  - Ensured comprehensive coverage of all success and failure scenarios in UserData and bootstrap scripts
  - Added comprehensive retry logic to all network operations in base.sh (NVM, Maven, Helm, download functions)
  - _Requirements: 6.2, 6.6_

- [x] 11.13 Resolve CDK template generation and String.format parameter alignment
  - Fixed String.format parameter count mismatch causing CDK synthesis failure (9 placeholders, 9 parameters)
  - Verified CloudFormation template generation works correctly with proper WaitConditionHandle references
  - Ensured all cfn-signal calls in generated template use WaitConditionHandle URL (Ref: IdeBootstrapWaitConditionHandleD7141CA8)
  - Validated template contains correct resource names: IdeBootstrapWaitConditionE4059F8E and IdeBootstrapWaitConditionHandleD7141CA8
  - Confirmed npm run generate produces valid CloudFormation template with all bootstrap signaling properly configured
  - _Requirements: 6.2, 6.6_

- [x] 11.14 Improve retry logging specificity and reduce verbosity
  - Updated retry_command function to accept tool_name parameter for concise success/failure messages
  - Changed from verbose "✅ Success: curl -LSsf -o /tmp/aws-cli.zip..." to concise "✅ Success: AWS CLI"
  - Applied tool-specific naming across all retry calls: "Java versions (8,17,21,25)", "NVM 0.40.3", "CDK and Artillery"
  - Maintained consistent retry logic across bootstrap.sh, vscode.sh, and base.sh with fallback implementations
  - Ensured all network operations show clear tool identification in both success and failure scenarios
  - _Requirements: 6.6, 6.7_

- [x] 11.17 Fix fallback retry function success logging consistency
  - Identified that vscode.sh and base.sh were using fallback retry implementations (no access to bootstrap's retry_command)
  - Updated fallback implementations to show success messages: "✅ Success: VS Code Server", "✅ Success: Caddy"
  - Fixed missing success logging for VS Code installation, extensions, Caddy, and all base development tools
  - Ensured consistent "✅ Success: [tool]" messages across all scripts regardless of execution context
  - All retry operations now show clear success/failure messages with tool identification
  - _Requirements: 6.6, 6.7_

- [x] 11.15 Fix CloudFormation output naming consistency
  - Fixed redundant resource naming: "IdeIdePassword" → "IdePassword", "IdeIdeUrl" → "IdeUrl"
  - Applied consistent naming pattern across all IDE-related resources
  - _Requirements: 6.3, 6.6_

- [x] 11.16 Implement Custom Resource Lambda for password output (matching original approach)
  - Created password-exporter.py Lambda following our coding standards (consistent with ec2-launcher.py)
  - Implemented Custom Resource that retrieves actual password from Secrets Manager during CloudFormation deployment
  - Updated CDK to use getIdePassword() method that creates Lambda function and Custom Resource
  - CloudFormation output now uses `Fn::GetAtt` to reference Custom Resource password attribute
  - Solution matches original infrastructure approach: Secrets Manager generates password → Lambda retrieves it → CloudFormation outputs actual value
  - Users will see real password (e.g., `IAysuSlT69eS2659acKGc84zLEX3SFxZ`) in CloudFormation outputs
  - Bootstrap script continues to work by fetching same password from Secrets Manager
  - _Requirements: 6.3_

- [x] 11.18 Disable VS Code agent panel and AI features
  - Updated VS Code settings.json to disable Agent Sessions view with `"chat.agentSessionsViewLocation": "off"`
  - Disabled GitHub Copilot features with `"github.copilot.enable": false` and `"github.copilot.chat.enable": false`
  - Disabled unified chat extension with `"chat.extensionUnification.enabled": false`
  - Prevents "Build with Agent" panel from appearing in VS Code Server 4.106.3
  - Provides clean coding environment without AI distractions for workshop participants
  - _Requirements: 6.8_

- [x] 11.19 Standardize success message format and add version detection
  - Unified all success messages to format: `✅ Success: [Tool Name] [Version]` (e.g., `✅ Success: Helm 3.19.3`)
  - Implemented `install_with_version` helper function to capture actual installed versions
  - Updated tools to show real versions: npm, CDK, Artillery, AWS SAM CLI, k9s, e1s
  - Removed redundant "download" suffixes and inconsistent naming patterns
  - Eliminated duplicate version logging and redundant verification messages
  - _Requirements: 6.6, 6.7_

- [x] 11.20 Clean up bootstrap scripts and remove redundancies
  - Removed all commented-out code blocks (EKSCTL, Docker Compose sections)
  - Eliminated redundant version logging after `install_with_version` usage
  - Cleaned up excessive blank lines and spacing inconsistencies
  - Updated outdated function comments and removed leftover artifacts
  - Consolidated Helm installation into single retry call
  - Standardized function usage across all scripts for consistency
  - _Requirements: 6.6, 6.7_

- [x] 11.21 Fix critical CloudFormation signaling architecture
  - Identified and fixed broken signaling flow where UserData had no fallback if bootstrap.sh failed to execute
  - Added comprehensive error trapping in UserData with `trap 'cfn-signal -e 1' ERR`
  - Implemented bulletproof signaling covering: UserData failures, repository clone failures, bootstrap execution failures, and bootstrap internal failures
  - Ensured immediate CloudFormation failure signals for all error conditions (no more 30-minute timeouts)
  - Maintained proper WAIT_CONDITION_HANDLE_URL environment variable passing to bootstrap.sh
  - Verified bootstrap.sh internal signaling (success/failure) works correctly with error traps
  - _Requirements: 6.2, 6.6_

- [x] 11.22 Implement IDE bootstrap summary logging
  - Added creation of `/home/ec2-user/ide-bootstrap.log` containing clean summary of all successful tool installations
  - Extracts `✅ Success:` messages from main bootstrap log using grep for easy workshop participant reference
  - Provides clean list of installed tools with versions (e.g., "✅ Success: Helm 3.19.3", "✅ Success: CDK 2.167.1")
  - Created at end of bootstrap process with proper ec2-user ownership and permissions
  - Enables workshop participants to easily verify available development tools with `cat ~/ide-bootstrap.log`
  - _Requirements: 6.6, 6.7_

- [x] 11.23 Replace error-prone String.format with reliable template variable approach
  - Replaced fragile String.format with manual placeholder counting with robust template variable system
  - Implemented `{{VARIABLE_NAME}}` placeholders with individual `.replace()` calls for each variable
  - Eliminated recurring parameter count misalignment errors that broke deployments multiple times
  - Created self-documenting UserData template where each variable replacement is explicit and clear
  - Verified template generation works correctly with all variables properly substituted in CloudFormation template
  - Improved maintainability - adding/removing variables no longer requires careful parameter counting
  - _Requirements: 6.2, 6.6_

- [x] 11.24 Fix UserData variable substitution in error handling paths
  - Fixed CloudFormation signaling failures caused by improper variable quoting in error handling paths
  - Changed single quotes to double quotes around `${WAIT_CONDITION_HANDLE_URL}` in cfn-signal calls
  - Ensured consistent variable substitution across all UserData script paths (success and failure scenarios)
  - Added proper environment variable passing to bootstrap script execution
  - Verified complete UserData flow from CDK template generation through bootstrap script execution
  - _Requirements: 6.2, 6.6, 11.5_

- [x] 11.25 Fix duplicate success messages and missing version information in bootstrap logs
  - Eliminated duplicate success messages for AWS SAM CLI and Session Manager Plugin by removing redundant download_and_verify calls
  - Added version detection for AWS CLI and CloudFormation helper scripts using install_with_version function
  - Fixed Artillery version command to use `artillery -v | head -1` for cleaner output
  - Improved Session Manager Plugin version detection with proper error handling
  - Fixed e1s version detection to properly extract version from "Current: v1.0.52" format using grep and awk
  - Ensured all tools show consistent "✅ Success: [Tool Name] [Version]" format without duplicates
  - _Requirements: 6.6, 6.7, 9.1, 9.2_

- [x] 11.26 Completely disable VS Code Agent panel and AI features
  - Added correct agent disabling setting: chat.agent.enabled set to false (verified from VS Code documentation)
  - Added chat.commandCenter.enabled: false to remove Chat menu from VS Code title bar (proven working)
  - Added workbench.settings.showAISearchToggle: false to disable AI search in settings (proven working)
  - Added chat.disableAIFeatures: true to disable and hide all built-in AI features provided by GitHub Copilot
  - Added chat.extensionUnification.enabled: false to disable experimental chat extension unification
  - Enhanced existing AI feature disabling with additional chat and panel controls
  - Eliminated the annoying "Ask about your code" panel that was still appearing despite previous settings
  - Ensured clean VS Code environment without any AI prompts or agent interfaces
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 11.27 Fix CDK construct naming to eliminate CloudFormation logical ID duplication
  - Fixed redundant CloudFormation logical IDs caused by duplicate naming patterns in CDK constructs
  - Updated Database construct: "DatabaseSecret" → "Secret", "DatabasePasswordSecret" → "PasswordSecret", "DatabaseCluster" → "Cluster"
  - Updated IDE construct: "IdePasswordSecret" → "PasswordSecret", "IdeRole" → "Role", "IdeSecurityGroup" → "SecurityGroup"
  - Updated EKS construct: "IdeInstanceAccessEntry" → "InstanceAccessEntry", "SecretsStoreCsiDriver" → "SecretsStoreDriver"
  - Updated CodeBuild and VPC constructs with consistent naming patterns
  - Eliminated problematic CloudFormation logical IDs: "IdeIdePasswordSecret" → "IdePasswordSecret", "DatabaseDatabaseSecret" → "DatabaseSecret"
  - Verified template generation produces clean logical IDs without duplication patterns
  - Applied consistent naming convention: construct name + resource type (e.g., Ide + PasswordSecret = IdePasswordSecret)
  - _Requirements: 1.1, 5.6_

- [x] 11.28 Implement consistent "workshop-" naming convention for all AWS resources
  - Updated Lambda function names to use "workshop-" prefix: "setup-codebuild-start" → "workshop-codebuild-start", "ide-ec2-launcher" → "workshop-ide-launcher"
  - Updated CodeBuild project name: "workshop-codebuild" → "workshop-setup" for consistency
  - Updated Database Lambda: "workshop-db-setup" → "workshop-database-setup" for clarity
  - Updated IDE Lambda functions: "ide-cloudfront-prefix-lookup" → "workshop-ide-prefixlist", dynamic password function → "workshop-ide-password"
  - Updated bootstrap log group: "ide-bootstrap-{timestamp}" → "workshop-ide-bootstrap-{timestamp}" for consistent grouping
  - Applied universal "workshop-{component}-{function}" naming pattern across all AWS resources
  - Enabled easy filtering and management of workshop resources in AWS console and CLI
  - _Requirements: 21.1, 21.2, 21.3, 21.4, 21.5_

## Java-on-AWS Migration (100.x)

- [x] 100.1 Analyze java-on-aws workshop requirements
  - Reviewed infrastructure/cfn/unicornstore-stack.yaml and identified required resources ✅
  - Documented EKS, Database, and other workshop-specific components ✅
  - Mapped existing resources to new construct pattern ✅
  - Planned conditional logic for WorkshopStack ✅
  - Referenced unicorn-roles-analysis.md for IAM role requirements ✅
  - _Requirements: 5.4, 5.5_

- [x] 100.2 Create EKS construct using EKS v2 with Auto Mode
  - Created infra/cdk/src/main/java/sample/com/constructs/Eks.java using software.amazon.awscdk.services.eks.v2.alpha ✅
  - Configured workshop-eks with Auto Mode, version 1.34, system+general-purpose node pools ✅
  - Added 3 EKS add-ons: AWS Secrets Store CSI Driver, AWS Mountpoint S3 CSI Driver, EKS Pod Identity Agent ✅
  - Created Access Entry for WSParticipantRole AND IDE instance role with cluster admin permissions ✅
  - Used Access Entries authentication mode instead of ConfigMap-based authentication ✅
  - Enabled all log types (api, audit, authenticator, controllerManager, scheduler) for comprehensive monitoring ✅
  - EKS cluster depends only on VPC for parallel deployment with Database ✅
  - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.7, 13.8, 15.3, 15.5, 15.6, 19.1_

- [x] 100.3 Create Database construct with universal naming
  - Create infra/cdk/src/main/java/sample/com/constructs/Database.java
  - Copy and refactor database setup from infrastructure/cdk/src/main/java/com/unicorn/core/DatabaseSetup.java
  - Update all database resource names to use "workshop-" prefix: cluster, writer, security group, subnet group
  - Change database name from "unicorns" to "workshop"
  - Update secrets names: "workshop-db-secret", "workshop-db-password-secret"
  - Update parameter store name: "workshop-db-connection-string"
  - Update IAM policy name: "workshop-db-secret-policy"
  - Update Lambda function name: "workshop-db-setup-lambda"
  - Integrate with new Vpc construct for proper subnet placement
  - Consolidate RDS and database schema setup into single construct
  - _Requirements: 5.6, 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_

- [x] 100.4 Update WorkshopStack for java-on-aws with EKS integration
  - Database already conditionally created for non-base templates (same as Roles) ✅
  - Added conditional EKS creation: if (!"base".equals(templateType) && !"java-ai-agents".equals(templateType)) ✅
  - Integrated EKS with IDE security group: eks.ideInternalSecurityGroup(ide.getIdeInternalSecurityGroup()) ✅
  - Integrated EKS with IDE instance role: eks.ideInstanceRole(ideProps.getIdeRole()) ✅
  - Tested TEMPLATE_TYPE=java-on-aws generates template with VPC, IDE, CodeBuild, Roles, Database, and EKS resources ✅
  - Validated generated template includes all EKS add-ons and Access Entries configuration ✅
  - Ensured template supports both java-on-aws and base templates from same codebase ✅
  - _Requirements: 1.2, 1.3, 13.1, 16.1_

- [x] 100.5 Create EKS post-deployment setup script
  - Created infra/scripts/setup/eks.sh for EKS cluster configuration (based on original infrastructure/scripts/setup/eks.sh) ✅
  - Used infra/scripts/lib/common.sh for consistent emoji-based logging and error handling ✅
  - Used infra/scripts/lib/wait-for-resources.sh wait_for_eks_cluster() function for cluster readiness ✅
  - Checked cluster status and wait until kubectl get ns works successfully before proceeding ✅
  - Updated kubeconfig and add workshop-eks to kubectl context ✅
  - Deployed GP3 StorageClass (encrypted, default) since EKS Auto Mode doesn't provide encrypted GP3 by default ✅
  - Deployed ALB IngressClass + IngressClassParams for Application Load Balancer integration ✅
  - Created SecretProviderClass for database secrets (workshop-db-secret, workshop-db-password-secret, workshop-db-connection-string) ✅
  - Configured EKS Pod Identity with AWSSecretsManagerClientReadOnlyAccess managed policy ✅
  - Verified all three add-ons are installed and functional before completing ✅
  - _Requirements: 15.1, 15.2, 14.2, 14.3, 14.4, 15.7, 18.1, 18.2, 18.3, 18.4, 18.6_

- [x] 100.6 Create java-on-aws workshop orchestration script
  - Created infra/scripts/ide/java-on-aws.sh that executes base.sh and EKS implementation ✅
  - Script calls base.sh first for foundational development tools ✅
  - Then executes EKS-specific setup (cluster configuration, add-ons, storage classes) ✅
  - Implemented proper error handling and progress feedback between base and EKS phases ✅
  - Tested script execution and validated all setup steps complete successfully ✅
  - _Requirements: 3.1, 3.2_

- [ ]* 100.7 Write property test for EKS Access Entry configuration
  - **Property 19: EKS Access Entry Configuration**
  - **Validates: Requirements 13.8**

- [ ]* 100.8 Write property test for workshop script orchestration
  - **Property 20: Workshop Script Orchestration**
  - **Validates: Requirements 17.1, 17.2**

- [ ]* 100.9 Write property test for workshop error handling
  - **Property 21: Workshop Error Handling**
  - **Validates: Requirements 17.3**

- [ ]* 100.10 Write property test for workshop verification
  - **Property 22: Workshop Verification**
  - **Validates: Requirements 17.4**

- [x] 100.11 Validate java-on-aws migration
  - Generated template with TEMPLATE_TYPE=java-on-aws and verified all EKS resources are present ✅
  - Tested template generation for both base and java-on-aws from same codebase ✅
  - Verified EKS add-ons, Access Entries, and database resources are properly configured ✅
  - Documented template differences and ensured they provide equivalent functionality ✅
  - _Requirements: 1.2, 1.3, 16.1_

## Java-on-EKS Migration (200.x)

- [ ] 200.1 Analyze and migrate java-on-eks workshop
  - Review infrastructure/cfn/java-on-eks-stack.yaml for specific requirements
  - Identify differences from java-on-aws (likely minimal, both use EKS)
  - Update WorkshopStack conditional logic if needed
  - Create infra/scripts/workshops/java-on-eks.sh orchestration script
  - _Requirements: 5.4, 5.5_

## Java-AI-Agents Migration (300.x)

- [ ] 300.1 Analyze and migrate java-ai-agents workshop
  - Review infrastructure/cfn/java-ai-agents-stack.yaml (no EKS, includes Bedrock permissions, has database)
  - Verify EKS exclusion logic: if (!"base".equals(workshopType) && !"java-ai-agents".equals(workshopType))
  - Database will be included automatically (non-base template)
  - Create infra/scripts/setup/ai-agents.sh for AI-specific setup
  - Create infra/scripts/workshops/java-ai-agents.sh orchestration script
  - _Requirements: 5.4, 5.5_

## Java-Spring-AI-Agents Migration (400.x)

- [ ] 400.1 Analyze and migrate java-spring-ai-agents workshop
  - Review infrastructure/cfn/spring-ai-stack.yaml for specific requirements
  - Create infra/scripts/setup/spring-ai.sh for Spring AI specific setup
  - Create infra/scripts/workshops/java-spring-ai-agents.sh orchestration script
  - Validate template generation and workshop setup scripts
  - _Requirements: 5.4, 5.5_

## Validation & Cleanup (1000.x)

- [ ] 1000.1 Comprehensive testing
  - Test template generation for all workshop types
  - Validate sync scripts copy templates and policies correctly
  - Test convention-based script discovery for all workshops
  - Verify error handling and timeout behavior in setup scripts
  - _Requirements: 3.4, 3.5, 4.5_

- [ ] 1000.2 Documentation and final validation
  - Update README with new infra/ usage instructions
  - Document migration process and parallel operation approach
  - Verify both infrastructure/ and infra/ systems can operate independently
  - Create migration checklist for workshop maintainers
  - _Requirements: 5.9_