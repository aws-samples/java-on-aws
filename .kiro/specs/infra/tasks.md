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

## Java-on-AWS Migration (100.x)

- [ ] 100.1 Analyze java-on-aws workshop requirements
  - Review infrastructure/cfn/unicornstore-stack.yaml to identify required resources
  - Document EKS, Database, and other workshop-specific components
  - Map existing resources to new construct pattern
  - Plan conditional logic for WorkshopStack
  - _Requirements: 5.4, 5.5_

- [ ] 100.2 Create EKS construct
  - Create infra/cdk/src/main/java/sample/com/constructs/Eks.java
  - Copy and refactor infrastructure/cdk/src/main/java/com/unicorn/constructs/EksCluster.java
  - Update to use EKS AutoMode and integrate with new Vpc and Roles constructs
  - Remove workshop-specific customizations, keep generic EKS setup
  - _Requirements: 5.6_

- [ ] 100.3 Create Database construct
  - Create infra/cdk/src/main/java/sample/com/constructs/Database.java
  - Copy and refactor database setup from infrastructure/cdk/src/main/java/com/unicorn/core/DatabaseSetup.java
  - Integrate with new Vpc construct for proper subnet placement
  - Consolidate RDS and database schema setup into single construct
  - _Requirements: 5.6_

- [ ] 100.4 Update WorkshopStack for java-on-aws
  - Add conditional EKS creation: if (!"ide".equals(workshopType) && !"java-ai-agents".equals(workshopType))
  - Add conditional Database creation: if (!"ide".equals(workshopType))
  - Test WORKSHOP_TYPE=java-on-aws generates template with all required resources
  - Validate generated template matches existing unicornstore-stack.yaml functionality
  - _Requirements: 1.2, 5.5_

- [ ] 100.5 Migrate java-on-aws setup scripts
  - Copy and refactor infrastructure/scripts/setup/eks.sh to infra/scripts/setup/eks.sh
  - Copy and refactor infrastructure/scripts/setup/app.sh to infra/scripts/setup/app.sh
  - Copy and refactor infrastructure/scripts/setup/monitoring.sh to infra/scripts/setup/monitoring.sh
  - Update all scripts with emoji-based logging and consistent error handling
  - _Requirements: 3.3, 5.7_

- [ ] 100.6 Create java-on-aws workshop orchestration script
  - Create infra/scripts/workshops/java-on-aws.sh
  - Orchestrate: base.sh, eks.sh, app.sh, monitoring.sh
  - Implement proper error handling and progress feedback
  - Test script execution and validate all setup steps complete successfully
  - _Requirements: 3.1, 3.2_

- [ ] 100.7 Validate java-on-aws migration
  - Generate template and compare with existing unicornstore-stack.yaml
  - Verify all required resources are present and properly configured
  - Test workshop deployment end-to-end (optional, can be done manually)
  - Document any differences and ensure they are acceptable
  - _Requirements: 5.5_

## Java-on-EKS Migration (200.x)

- [ ] 200.1 Analyze and migrate java-on-eks workshop
  - Review infrastructure/cfn/java-on-eks-stack.yaml for specific requirements
  - Identify differences from java-on-aws (likely minimal, both use EKS)
  - Update WorkshopStack conditional logic if needed
  - Create infra/scripts/workshops/java-on-eks.sh orchestration script
  - _Requirements: 5.4, 5.5_

## Java-AI-Agents Migration (300.x)

- [ ] 300.1 Analyze and migrate java-ai-agents workshop
  - Review infrastructure/cfn/java-ai-agents-stack.yaml (no EKS, includes Bedrock permissions)
  - Verify EKS exclusion logic: if (!"java-ai-agents".equals(workshopType))
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

name or just value?