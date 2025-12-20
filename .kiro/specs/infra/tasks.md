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
  - Create infra/scripts/cfn/sync.sh that copies cfn/{workshop}-stack.yaml → workshop-stack.yaml ✅
  - Copy workshop-specific IAM policies (iam-policy-{workshop}.json → iam-policy.json) ✅
  - Target files use static names: workshop-stack.yaml and iam-policy.json ✅
  - Implement directory existence checking and error reporting ✅
  - Support workshop list: ide, java-on-aws-immersion-day, java-on-amazon-eks, java-ai-agents, java-spring-ai-agents ✅
  - _Requirements: 4.2, 4.5_

- [x] 2.3 Set up build automation
  - Create infra/package.json with generate and sync npm scripts ✅
  - Make scripts executable and test npm run generate && npm run sync workflow ✅
  - Validate that generated templates are copied to correct locations with proper naming ✅
  - Workshop-specific IAM policies stored as iam-policy-{workshop}.json in cdk/src/main/resources/ ✅
  - Ide.java loads iam-policy-{templateType}.json and throws exception if not found ✅
  - Created iam-policy-base.json with Allow * for base template ✅
  - _Requirements: 4.3_

## Base IDE Stack (10.x)

- [x] 10.1 Create core CDK constructs
  - Created infra/cdk/src/main/java/sample/com/constructs/Vpc.java for VPC with 2 AZs and 1 NAT gateway ✅
  - Created infra/cdk/src/main/java/sample/com/constructs/Ide.java for VS Code IDE environment ✅
  - Created infra/cdk/src/main/java/sample/com/constructs/CodeBuild.java for workshop setup automation ✅
  - Created infra/cdk/src/main/java/sample/com/constructs/Lambda.java for reusable Lambda function creation ✅
  - _Requirements: 1.1, 5.6_

- [x] 10.2 Migrate and refactor IAM roles into Unicorn construct
  - Replaced standalone Roles.java with Unicorn.java that combines ECR + IAM roles ✅
  - IAM roles embedded in Unicorn construct for workshop content compatibility ✅
  - Uses unicorn* naming convention for workshop application compatibility ✅
  - Include Bedrock permissions for AI workshops in the unified roles ✅
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

## Java-on-AWS-Immersion-Day Migration (100.x)

- [x] 100.1 Analyze java-on-aws-immersion-day workshop requirements
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
  - Created Access Entry for IDE instance role with cluster admin permissions ✅
  - WSParticipantRole Access Entry removed after testing showed it's not needed ✅
  - Used Access Entries authentication mode instead of ConfigMap-based authentication ✅
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

- [x] 100.4 Update WorkshopStack for java-on-aws-immersion-day with EKS integration
  - Database already conditionally created for non-base templates (same as Roles) ✅
  - Added conditional EKS creation: if (!"base".equals(templateType) && !"java-ai-agents".equals(templateType)) ✅
  - Integrated EKS with IDE security group: eks.ideInternalSecurityGroup(ide.getIdeInternalSecurityGroup()) ✅
  - Integrated EKS with IDE instance role: eks.ideInstanceRole(ideProps.getIdeRole()) ✅
  - Tested TEMPLATE_TYPE=java-on-aws-immersion-day generates template with VPC, IDE, CodeBuild, Roles, Database, and EKS resources ✅
  - Validated generated template includes all EKS add-ons and Access Entries configuration ✅
  - Ensured template supports both java-on-aws-immersion-day and base templates from same codebase ✅
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

- [x] 100.6 Create java-on-aws-immersion-day workshop orchestration script
  - Created infra/scripts/templates/java-on-aws-immersion-day.sh that executes base.sh and workshop-specific setup ✅
  - Script calls base.sh first for foundational development tools ✅
  - Then executes EKS-specific setup (cluster configuration, add-ons, storage classes) ✅
  - Added Phase 3: Monitoring stack (Prometheus + Grafana) via monitoring.sh ✅
  - Added Phase 4: Analysis (thread dump + profiling) via analysis.sh ✅
  - Implemented proper error handling and progress feedback between all phases ✅
  - _Requirements: 3.1, 3.2_

- [x] 100.17 Create monitoring stack setup script
  - Created infra/scripts/setup/monitoring.sh for Prometheus + Grafana deployment ✅
  - Deploys Prometheus with 24h retention and 15s scrape interval ✅
  - Deploys Grafana with LoadBalancer service and persistent storage ✅
  - Configures Prometheus datasource automatically via ConfigMap sidecar ✅
  - Uses workshop-ide-password from Secrets Manager for Grafana admin credentials ✅
  - _Requirements: 5.6_

- [x] 100.20 Consolidate analysis scripts into single analysis.sh
  - Merged analysis-thread.sh and analysis-profiling.sh into infra/scripts/setup/analysis.sh ✅
  - Use single shared folder "Workshop Dashboards" for all dashboards ✅
  - SECTION 1 - Thread Analysis:
    - Build and deploy thread-dump-lambda ✅
    - Create JVM Metrics dashboard (thread count, memory usage) ✅
    - Create "lambda-webhook" contact point ✅
    - Create "High JVM Threads" alert rule (>200 threshold) ✅
    - Test Bedrock model access ✅
  - SECTION 2 - Profiling Analysis:
    - Create HTTP Metrics dashboard (POST request rate) ✅
    - Create "jvm-analysis-webhook" contact point ✅
    - Create "High HTTP POST Request Rate" alert rule (>20 req/s threshold) ✅
  - Configure single notification policy with nested routes for both contact points ✅
  - Deleted old analysis-thread.sh and analysis-profiling.sh files ✅
  - Updated java-on-aws.sh to call analysis.sh instead of two separate scripts ✅
  - _Requirements: 5.6_

- [x] 100.21 Restructure scripts into ide/ and templates/ directories
  - Renamed base.sh to tools.sh and kept in ide/ folder ✅
  - Renamed ide-settings.sh to settings.sh (removed redundant ide- prefix) ✅
  - Updated bootstrap.sh to call tools.sh as part of default IDE setup (after vscode/code-editor) ✅
  - Created templates/ directory for workshop-specific post-deploy scripts ✅
  - Created templates/base.sh as empty placeholder with comment ✅
  - Moved java-on-aws-immersion-day.sh to templates/java-on-aws-immersion-day.sh ✅
  - Updated java-on-aws-immersion-day.sh to NOT call base (tools already installed by bootstrap) ✅
  - Updated bootstrap.sh to look for template scripts in templates/ folder ✅
  - Updated vscode.sh and code-editor.sh to use settings.sh ✅
  - Final structure:
    - ide/bootstrap.sh → ide/{IDE_TYPE}.sh → ide/tools.sh (IDE setup complete)
    - ide/bootstrap.sh → templates/{TEMPLATE_TYPE}.sh (workshop post-deploy)
  - _Requirements: 3.1, 5.7_

- [x] 100.22 Rename p10k.zsh to shell-p10k.zsh for clarity
  - Renamed infra/scripts/ide/p10k.zsh to shell-p10k.zsh ✅
  - Updated shell.sh to reference shell-p10k.zsh instead of p10k.zsh ✅
  - Naming convention indicates p10k config is associated with shell.sh ✅
  - _Requirements: 5.7_

- [x] 100.23 Standardize logging and improve script reliability
  - Updated monitoring.sh to use lib/common.sh for consistent logging (log_info, log_success, log_error) ✅
  - Updated analysis.sh to use lib/common.sh for consistent logging ✅
  - Fixed analysis.sh cd issue by using subshell: (cd "$BUILD_DIR/package" && zip ...) ✅
  - Added port-forward cleanup trap in monitoring.sh to prevent zombie processes ✅
  - Added "✅ Success:" summary lines at end of major components for bootstrap summary capture:
    - eks.sh: "✅ Success: EKS cluster (workshop-eks)" ✅
    - monitoring.sh: "✅ Success: Monitoring (Prometheus + Grafana)" ✅
    - analysis.sh: "✅ Success: Analysis (Thread + Profiling dashboards)" ✅
    - java-on-aws-immersion-day.sh: "✅ Success: Java-on-AWS-Immersion-Day workshop template" ✅
  - _Requirements: 3.3, 3.7, 6.6_



- [x] 100.11 Validate java-on-aws-immersion-day migration
  - Generated template with TEMPLATE_TYPE=java-on-aws-immersion-day and verified all EKS resources are present ✅
  - Tested template generation for both base and java-on-aws-immersion-day from same codebase ✅
  - Verified EKS add-ons, Access Entries, and database resources are properly configured ✅
  - Documented template differences and ensured they provide equivalent functionality ✅
  - _Requirements: 1.2, 1.3, 16.1_

- [x] 100.12 Create PerformanceAnalysis construct with shared resources
  - Created infra/cdk/src/main/java/sample/com/constructs/PerformanceAnalysis.java ✅
  - Implemented shared S3 bucket (workshop-{account}-{region}-{timestamp}) for thread dumps and profiling data ✅
  - Created SSM parameter (workshop-analysis-bucket-name) for bucket name discovery ✅
  - Created Lambda Bedrock role (workshop-analysis-lambda-role) with EKS + ECS access permissions ✅
  - Added Bedrock InvokeModel permissions for AI-powered analysis ✅
  - _Requirements: 5.6_

- [x] 100.13 Add ThreadAnalysis sub-construct
  - Implemented Thread Dump Lambda (workshop-thread-dump-lambda) with VPC placement ✅
  - Created Lambda Security Group (workshop-analysis-lambda-sg) with VPC CIDR ingress ✅
  - Created Private API Gateway (workshop-thread-dump-api) with VPC endpoint ✅
  - Added EKS Access Entry for Lambda role with cluster admin policy ✅
  - Created CloudWatch Log Group (/aws/lambda/workshop-thread-dump-lambda) with 7-day retention ✅
  - Configured security group rules for Lambda to access EKS cluster API ✅
  - _Requirements: 5.6_

- [x] 100.14 Add ProfilingAnalysis sub-construct
  - Created ECR repository (jvm-analysis-service) for async-profiler analysis service ✅
  - Created Pod Identity role (jvm-analysis-service-eks-pod-role) for EKS workloads ✅
  - Added AmazonBedrockLimitedAccess managed policy for AI analysis ✅
  - Configured S3 permissions for profiling data (ListBucket, GetObject, PutObject) ✅
  - Both ThreadAnalysis and ProfilingAnalysis enabled by default ✅
  - _Requirements: 5.6_

- [x] 100.15 Integrate PerformanceAnalysis into WorkshopStack
  - Added conditional PerformanceAnalysis creation for java-on-aws-immersion-day template type ✅
  - Passed EKS cluster reference for Access Entry creation ✅
  - Passed VPC reference for Lambda VPC placement ✅
  - Tested template generation with PerformanceAnalysis resources ✅
  - Verified all resources present in generated java-on-aws-immersion-day-stack.yaml ✅
  - _Requirements: 1.2, 1.3_

- [x] 100.16 Create thread-dump-lambda.py implementation
  - Created infra/cdk/src/main/resources/lambda/thread-dump-lambda.py ✅
  - Implemented EKS pod discovery and thread dump collection ✅
  - Added Bedrock integration for AI-powered thread analysis ✅
  - Store results in S3 bucket with proper prefixes ✅
  - _Requirements: 5.6_

- [x] 100.24 Create Unicorn construct with ECR and Roles
  - Created infra/cdk/src/main/java/sample/com/constructs/Unicorn.java ✅
  - Uses "unicorn*" naming for workshop content compatibility ✅
  - ECR repository: `unicorn-store-spring` ✅
  - EKS Roles (conditional):
    - `unicornstore-eks-pod-role` - EKS Pod Identity (X-Ray, CloudWatch, Bedrock, S3, DB secrets) ✅
  - ECS Roles (conditional):
    - `unicornstore-ecs-task-role` - ECS task role (X-Ray, CloudWatch, SSM, DB secrets) ✅
    - `unicornstore-ecs-task-execution-role` - ECS execution role ✅
  - Accepts Database and S3 bucket references for permission grants ✅
  - Integrated into WorkshopStack for non-base templates ✅
  - Note: ESO roles not needed - replaced by AWS Secrets Store CSI Driver add-on
  - _Requirements: 5.6_

## Java-on-Amazon-EKS Template (200.x)

- [x] 200.1 Create java-on-amazon-eks template (same infrastructure as java-on-aws-immersion-day)
  - Updated WorkshopStack.java to include java-on-amazon-eks in same conditional as java-on-aws-immersion-day ✅
  - Updated generate.sh to generate java-on-amazon-eks-stack.yaml template ✅
  - Created infra/scripts/templates/java-on-amazon-eks.sh (same setup as java-on-aws-immersion-day.sh) ✅
  - Created infra/cdk/src/main/resources/iam-policy-java-on-amazon-eks.json (copy of java-on-aws-immersion-day policy) ✅
  - Template includes: VPC, IDE, CodeBuild, Database, EKS, PerformanceAnalysis, Unicorn ✅
  - _Requirements: 1.2, 1.3, 5.4_

## Java-AI-Agents Migration (300.x)

- [x] 300.1 Create java-ai-agents template (same infrastructure as base)
  - Updated generate.sh to generate java-ai-agents-stack.yaml template ✅
  - Created infra/scripts/templates/java-ai-agents.sh (minimal setup, no EKS/Database) ✅
  - Created infra/cdk/src/main/resources/iam-policy-java-ai-agents.json (Allow * like base) ✅
  - Template includes: VPC, IDE, CodeBuild only (same as base) ✅
  - No EKS, Database, PerformanceAnalysis, or Unicorn resources ✅
  - _Requirements: 1.2, 1.3, 5.4_

## Java-Spring-AI-Agents Template (400.x)

- [x] 400.1 Create java-spring-ai-agents template (same infrastructure as base)
  - Updated generate.sh to generate java-spring-ai-agents-stack.yaml template ✅
  - Created infra/scripts/templates/java-spring-ai-agents.sh (minimal setup, no EKS/Database) ✅
  - Created infra/cdk/src/main/resources/iam-policy-java-spring-ai-agents.json (Allow * like base) ✅
  - Template includes: VPC, IDE only (same as base) ✅
  - No EKS, Database, PerformanceAnalysis, or Unicorn resources ✅
  - _Requirements: 1.2, 1.3, 5.4_



## Configurable Prefix Pattern (500.x)

- [x] 500.1 Add prefix constant to WorkshopStack
  - Add `String prefix = "workshop";` at the very beginning of WorkshopStack constructor (before configuration values) ✅
  - Pass prefix to all construct Props builders (Vpc, Ide, CodeBuild, Database, Eks) ✅
  - Do NOT pass prefix to Unicorn or JvmAnalysis (they have their own naming) ✅
  - _Requirements: 22.1, 22.2, 22.6, 22.7_

- [x] 500.2 Update Vpc construct for configurable prefix
  - Add prefix parameter to VpcProps ✅
  - Update VPC name to use `{prefix}-vpc` pattern ✅
  - _Requirements: 22.2, 22.3_

- [x] 500.3 Update Ide construct for configurable prefix
  - Add prefix parameter to IdeProps ✅
  - Update Lambda function names: `{prefix}-ide-launcher`, `{prefix}-ide-password`, `{prefix}-ide-prefixlist` ✅
  - Update CloudWatch log group: `{prefix}-ide-bootstrap-{timestamp}` ✅
  - Update security group names to use prefix ✅
  - Update instance profile name to use prefix ✅
  - Update password secret name to use prefix ✅
  - _Requirements: 22.2, 22.3_

- [x] 500.4 Update CodeBuild construct for configurable prefix
  - Add prefix parameter to CodeBuildProps ✅
  - Update CodeBuild project name: `{prefix}-setup` ✅
  - Update Lambda function names: `{prefix}-codebuild-start`, `{prefix}-codebuild-report` ✅
  - _Requirements: 22.2, 22.3_

- [x] 500.5 Update Database construct for configurable prefix
  - Add prefix parameter to DatabaseProps ✅
  - Update cluster name: `{prefix}-db-cluster` ✅
  - Update instance name: `{prefix}-db-writer` ✅
  - Update secrets names: `{prefix}-db-secret`, `{prefix}-db-password-secret` ✅
  - Update parameter store: `{prefix}-db-connection-string` ✅
  - Update security group name to use prefix ✅
  - _Requirements: 22.2, 22.3_

- [x] 500.6 Update Eks construct for configurable prefix
  - Add prefix parameter to EksProps ✅
  - Update cluster name: `{prefix}-eks` ✅
  - _Requirements: 22.2, 22.3_

- [x] 500.7 Update bootstrap scripts for configurable prefix
  - Pass PREFIX environment variable from CDK to UserData ✅
  - Update userdata.sh to use PREFIX for log group names ✅
  - Update bootstrap.sh to use PREFIX for secret name lookup ✅
  - Update eks.sh to use PREFIX for cluster name and SecretProviderClass ✅
  - Update monitoring.sh and analysis.sh to use PREFIX ✅
  - _Requirements: 22.2, 22.3_

- [x] 500.8 Test and validate configurable prefix
  - Generate template with default prefix: `npm run generate` ✅
  - Verify all resources (except Unicorn and JvmAnalysis) use "workshop-" prefix ✅
  - Verify generated CloudFormation template has all names resolved (no parameters) ✅
  - _Requirements: 22.4, 22.5_


## PerformanceAnalysis Refactoring (600.x)

- [x] 600.1 Create WorkshopBucket construct
  - Create infra/cdk/src/main/java/sample/com/constructs/WorkshopBucket.java ✅
  - Add prefix parameter to WorkshopBucketProps ✅
  - Create S3 bucket: `{prefix}-bucket-{account}-{region}-{timestamp}` ✅
  - Create SSM parameter: `{prefix}-bucket-name` ✅
  - Expose bucket and parameter as getters ✅
  - _Requirements: 23.1, 23.2, 23.3_

- [x] 600.2 Create ThreadAnalysis construct
  - Create infra/cdk/src/main/java/sample/com/constructs/ThreadAnalysis.java ✅
  - Add prefix parameter to ThreadAnalysisProps ✅
  - Create thread dump Lambda: `{prefix}-thread-dump-lambda` ✅
  - Create API Gateway: `{prefix}-thread-dump-api` ✅
  - Create Lambda role: `{prefix}-thread-dump-lambda-role` ✅
  - Create security group: `{prefix}-thread-dump-lambda-sg` ✅
  - Create log group: `/aws/lambda/{prefix}-thread-dump-lambda` ✅
  - Accept WorkshopBucket reference for S3 permissions ✅
  - _Requirements: 24.1, 24.2, 24.3, 24.4, 24.5_

- [x] 600.3 Create JvmAnalysis construct
  - Create infra/cdk/src/main/java/sample/com/constructs/JvmAnalysis.java ✅
  - Create ECR repository: `jvm-analysis-service` (no prefix) ✅
  - Create Pod Identity role: `jvm-analysis-service-eks-pod-role` (no prefix) ✅
  - Accept WorkshopBucket reference for S3 permissions ✅
  - _Requirements: 25.1, 25.2, 25.3_

- [x] 600.4 Update WorkshopStack for new constructs
  - Add prefix to WorkshopBucket, ThreadAnalysis creation ✅
  - Create WorkshopBucket first (shared resource) ✅
  - Pass WorkshopBucket to ThreadAnalysis and JvmAnalysis ✅
  - Pass WorkshopBucket to Unicorn (replaces performanceAnalysis.getWorkshopBucket()) ✅
  - Remove PerformanceAnalysis construct usage ✅
  - _Requirements: 22.2, 23.3_

- [x] 600.5 Delete PerformanceAnalysis construct
  - Delete infra/cdk/src/main/java/sample/com/constructs/PerformanceAnalysis.java ✅
  - Verify all functionality moved to new constructs ✅
  - _Requirements: 23.1, 24.1, 25.1_

- [x] 600.6 Test and validate refactoring
  - Generate template: `npm run generate` ✅
  - Verify WorkshopBucket resources use prefix ✅
  - Verify ThreadAnalysis resources use prefix ✅
  - Verify JvmAnalysis resources use app-specific naming (no prefix) ✅
  - Verify Unicorn still receives bucket reference ✅
  - _Requirements: 22.5, 23.3, 24.1, 25.1_


## ECR Create-on-Push (700.x)

- [x] 700.1 Create EcrRegistry construct
  - Create infra/cdk/src/main/java/sample/com/constructs/EcrRegistry.java
  - Add prefix parameter to EcrRegistryProps
  - Create CfnRepositoryCreationTemplate with:
    - prefix: "ROOT" (applies to all repositories)
    - appliedFor: ["CREATE_ON_PUSH", "REPLICATION"]
    - imageTagMutability: "MUTABLE"
    - lifecyclePolicy: JSON with 1-day untagged expiry and 10 recent tagged retention
    - resourceTags: Environment={prefix}, ManagedBy=ecr-create-on-push
    - description: "Auto-create repositories on push with lifecycle policies for {prefix} workshop"
  - _Requirements: 26.1, 26.2, 26.3, 27.1, 27.2, 29.1, 29.2_

- [x] 700.2 Remove ECR repository from Unicorn construct
  - Remove Repository.Builder.create() for unicorn-store-spring from Unicorn.java
  - Remove unicornStoreSpringEcr field and getter
  - Update any code that references the ECR repository
  - Verify construct still compiles and functions correctly
  - _Requirements: 28.1_

- [x] 700.3 Remove ECR repository from JvmAnalysis construct
  - Remove Repository.Builder.create() for jvm-analysis-service from JvmAnalysis.java
  - Remove jvmAnalysisEcr field and getter
  - Update any code that references the ECR repository
  - Verify construct still compiles and functions correctly
  - _Requirements: 28.2_

- [x] 700.4 Integrate EcrRegistry into WorkshopStack
  - Add EcrRegistry creation for java-on-aws-immersion-day and java-on-amazon-eks templates
  - Create EcrRegistry before Unicorn and JvmAnalysis constructs
  - Pass prefix to EcrRegistry
  - _Requirements: 26.1, 28.3_

- [x] 700.5 Test and validate ECR Create-on-Push
  - Generate template: `npm run generate`
  - Verify CfnRepositoryCreationTemplate resource is present in generated template
  - Verify Unicorn construct no longer creates ECR repository
  - Verify JvmAnalysis construct no longer creates ECR repository
  - Verify lifecycle policy JSON is correctly formatted
  - Verify resource tags are present
  - _Requirements: 26.1, 26.2, 26.3, 27.1, 27.2, 28.1, 28.2, 29.1, 29.2_

- [x] 700.6 Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.


## IAM Policy Consolidation (800.x)

- [x] 800.1 Consolidate IAM policy files
  - Create single iam-policy.json from java-on-aws-immersion-day.json
  - Add bedrock-agentcore:* permission for AI agent workshops
  - Delete duplicate policy files:
    - iam-policy-base.json
    - iam-policy-java-on-aws-immersion-day.json
    - iam-policy-java-on-amazon-eks.json
    - iam-policy-java-ai-agents.json
    - iam-policy-java-spring-ai-agents.json
  - _Requirements: 5.6_

- [x] 800.2 Update Ide.java policy loading logic
  - For base template: use AdministratorAccess managed policy
  - For all other templates: load iam-policy.json
  - Remove template-specific policy file loading
  - _Requirements: 5.6_

- [x] 800.3 Test and validate IAM policy consolidation
  - Generate all templates: `npm run generate`
  - Verify base template uses AdministratorAccess
  - Verify other templates use custom IdeUserPolicy
  - _Requirements: 5.6_


## VPC Endpoint Cleanup and SSM Parameters (900.x)

- [x] 900.1 Create VPC Endpoint Cleanup construct
  - Create infra/cdk/src/main/resources/lambda/cfn-pre-delete-cleanup.py
  - Lambda finds GuardDuty VPC endpoints by VPC ID, deletes them, waits for deletion
  - Create infra/cdk/src/main/java/sample/com/constructs/CfnPreDeleteCleanup.java
  - Custom Resource triggers cleanup on stack delete only
  - _Requirements: 5.6_

- [x] 900.2 Integrate CfnPreDeleteCleanup into WorkshopStack
  - Add CfnPreDeleteCleanup for java-on-aws-immersion-day and java-on-amazon-eks templates
  - Pass VPC ID to ensure only workshop VPC endpoints are deleted
  - _Requirements: 5.6_

- [x] 900.3 Add workshop-vpc-id SSM parameter
  - Update Vpc.java to create SSM parameter with VPC ID
  - Parameter name: workshop-vpc-id
  - Available in all stacks for cross-stack reference
  - _Requirements: 5.6_

- [x] 900.4 Test and validate
  - Generate all templates: `npm run generate`
  - Verify CfnPreDeleteCleanup resources in EKS templates
  - Verify workshop-vpc-id SSM parameter in all templates
  - _Requirements: 5.6_


## CDK Nag Integration (1000.x)

- [x] 1000.1 Add CDK Nag dependency
  - Add io.github.cdklabs:cdknag:2.36.2 to pom.xml
  - Add cdknag.version property for version management
  - _Requirements: 5.6_

- [x] 1000.2 Configure CDK Nag in WorkshopApp
  - Add AwsSolutionsChecks aspect to app
  - Add workshop-appropriate suppressions for:
    - API Gateway (APIG1-6, COG4) - no auth/logging needed for workshop
    - IAM (IAM4, IAM5) - managed policies and wildcards acceptable
    - RDS (RDS2, RDS3, RDS6, RDS10, RDS11, RDS13) - ephemeral workshop database
    - VPC (VPC7, EC23) - no flow logs needed
    - Secrets Manager (SMG4) - no rotation needed
    - CloudFront (CFR1-5) - HTTP origin acceptable for workshop
    - EKS (EKS1, EKS2) - public access and no logging for workshop
    - EC2 (EC28, EC29) - no autoscaling/termination protection
    - CodeBuild (CB4) - default CMK acceptable
    - S3 (S1) - no access logs needed
    - Lambda (L1) - CDK default runtimes acceptable
    - ELB (ELB2) - no ALB logs needed
    - ECS (ECS2, ECS4) - temporary containers, no insights
  - _Requirements: 5.6_

- [x] 1000.3 Enable SSL enforcement on S3 bucket
  - Add enforceSsl(true) to WorkshopBucket construct
  - Fixes AwsSolutions-S10 CDK Nag finding
  - _Requirements: 5.6_

- [x] 1000.4 Test and validate CDK Nag
  - Generate all templates: `npm run generate`
  - Verify no CDK Nag errors (only suppressed warnings)
  - All templates pass validation
  - _Requirements: 5.6_


## S3 HTTPS Verification (1100.x)

- [x] 1100.1 Verify S3 bucket SSL enforcement
  - WorkshopBucket.java has enforceSsl(true) which enforces HTTPS at bucket policy level ✅
  - Any HTTP requests to the bucket will be denied by AWS ✅
  - _Requirements: 5.6_

- [x] 1100.2 Verify S3 client usage in Lambda
  - thread-dump-lambda/src/index.py uses boto3.client('s3') for put_object operations ✅
  - boto3 S3 client uses HTTPS by default - no code changes needed ✅
  - S3 operations: put_object for thread dumps and analysis results ✅
  - _Requirements: 5.6_

- [x] 1100.3 Verify S3 permissions in CDK constructs
  - ThreadAnalysis.java passes bucket name to Lambda via S3_BUCKET_NAME environment variable ✅
  - JvmAnalysis.java grants S3 permissions to Pod Identity role ✅
  - Unicorn.java grants S3 permissions to EKS pod role ✅
  - All use bucket.grantReadWrite() which doesn't affect transport protocol ✅
  - _Requirements: 5.6_

- [x] 1100.4 Verify scripts don't use HTTP for S3
  - tools.sh Session Manager download uses AWS-hosted URL (not our bucket) - acceptable ✅
  - No scripts manually construct S3 URLs that might use HTTP ✅
  - All S3 interactions go through AWS SDK/CLI which use HTTPS by default ✅
  - _Requirements: 5.6_


## Unicorn Store Spring Setup (1200.x)

- [x] 1200.1 Create unicorn-store-spring.sh setup script
  - Created infra/scripts/setup/unicorn-store-spring.sh ✅
  - Copies ~/java-on-aws/apps/unicorn-store-spring to ~/environment ✅
  - Logs in to ECR using aws ecr get-login-password ✅
  - Builds Docker image with docker build ✅
  - Tags and pushes with 'initial' tag ✅
  - Tags and pushes with 'latest' tag ✅
  - Emits "✅ Success: Unicorn Store Spring" for bootstrap summary ✅
  - _Requirements: 5.6_

- [x] 1200.2 Integrate into java-on-aws-immersion-day template
  - Added Phase 4: Unicorn Store Spring to java-on-aws-immersion-day.sh ✅
  - Calls unicorn-store-spring.sh after analysis setup ✅
  - _Requirements: 5.6_

- [x] 1200.3 Integrate into java-on-amazon-eks template
  - Added Phase 4: Unicorn Store Spring to java-on-amazon-eks.sh ✅
  - Calls unicorn-store-spring.sh after analysis setup ✅
  - _Requirements: 5.6_


## Stack Cleanup Enhancements (1300.x)

- [x] 1300.1 Enhance cleanup Lambda with CloudWatch logs and S3 cleanup
  - Updated cfn-pre-delete-cleanup.py to also clean up CloudWatch logs and S3 buckets ✅
  - Deletes log groups with workshop- or unicornstore- prefix ✅
  - Empties S3 buckets with workshop- prefix ✅
  - Execution order: start VPC endpoint deletion → cleanup logs and S3 → wait for VPC endpoints ✅
  - _Requirements: 5.6_

- [x] 1300.2 Update CfnPreDeleteCleanup construct with additional IAM permissions
  - Added logs:DescribeLogGroups and logs:DeleteLogGroup permissions ✅
  - Added s3:ListAllMyBuckets, s3:ListBucket, s3:ListBucketVersions, s3:DeleteObject, s3:DeleteObjectVersion permissions ✅
  - Updated Lambda description to reflect expanded cleanup scope ✅
  - _Requirements: 5.6_

- [x] 1300.3 Rename construct and Lambda for clarity
  - Renamed VpcEndpointCleanup.java to CfnPreDeleteCleanup.java ✅
  - Renamed vpc-endpoint-cleanup.py to cfn-pre-delete-cleanup.py ✅
  - Updated Lambda function name to {prefix}-cfn-pre-delete-cleanup ✅
  - Updated WorkshopStack.java to use new class name ✅
  - _Requirements: 5.6_
