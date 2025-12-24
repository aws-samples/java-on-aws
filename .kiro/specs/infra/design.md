# Infrastructure Refactoring Design Document

## Overview

This design document outlines the architecture for a new unified AWS workshop infrastructure system. The system uses a convention-based approach with a single CDK codebase that generates different CloudFormation templates based on workshop type. The design emphasizes modularity, automation, and parallel deployment to create an efficient and maintainable infrastructure management system.

## Architecture

### Core Concept

The architecture follows a **CDK → CloudFormation → Workshop Studio** workflow with convention-based conditional deployment. A single CDK application determines which resources to create based on the workshop type specified via environment variables.

### Directory Structure

```
infra/
├── cdk/
│   ├── src/main/java/sample/com/
│   │   ├── constructs/           # Reusable constructs
│   │   │   ├── Vpc.java
│   │   │   ├── Ide.java
│   │   │   ├── Eks.java
│   │   │   ├── Database.java
│   │   │   ├── CodeBuild.java
│   │   │   ├── Lambda.java
│   │   │   ├── PerformanceAnalysis.java
│   │   │   └── Unicorn.java      # ECR + IAM roles (uses unicorn* naming for workshop compatibility)
│   │   ├── WorkshopStack.java    # Main stack
│   │   └── WorkshopApp.java      # Main CDK application
│   ├── src/main/resources/
│   │   ├── userdata.sh           # Minimal UserData script (embedded in CDK)
│   │   ├── iam-policy-base.json
│   │   ├── iam-policy-java-on-aws-immersion-day.json
│   │   ├── iam-policy-java-on-amazon-eks.json
│   │   ├── iam-policy-java-ai-agents.json
│   │   ├── iam-policy-java-spring-ai-agents.json
│   │   └── lambda/               # Lambda function source files
│   │       ├── ec2-launcher.py
│   │       ├── codebuild-start.py
│   │       ├── codebuild-report.py
│   │       ├── password-exporter.py
│   │       ├── database-setup.py
│   │       ├── cloudfront-prefix-lookup.py
│   │       └── thread-dump-lambda.py
│   ├── pom.xml
│   └── cdk.json
├── cfn/                         # Generated CloudFormation templates
│   ├── base-stack.yaml
│   ├── java-on-aws-immersion-day-stack.yaml
│   ├── java-on-amazon-eks-stack.yaml
│   ├── java-ai-agents-stack.yaml
│   └── java-spring-ai-agents-stack.yaml
├── scripts/
│   ├── ide/                     # IDE setup scripts
│   │   ├── functions.sh         # Shared helper functions (retry, logging, install)
│   │   ├── bootstrap.sh         # Full bootstrap orchestration (jq, Docker, AWS CLI, env vars)
│   │   ├── vscode.sh            # VS Code Server installation
│   │   ├── code-editor.sh       # AWS Code Editor installation
│   │   ├── tools.sh             # Base development tools
│   │   ├── settings.sh          # IDE settings configuration
│   │   ├── shell.sh             # Shell UX (zsh + oh-my-zsh + p10k)
│   │   └── shell-p10k.zsh       # Powerlevel10k configuration
│   ├── templates/               # Workshop-specific post-deploy scripts
│   │   ├── base.sh              # Base template (empty placeholder)
│   │   ├── java-on-aws-immersion-day.sh  # Java-on-AWS Immersion Day workshop setup
│   │   ├── java-on-amazon-eks.sh         # Java-on-Amazon-EKS workshop setup (same as java-on-aws-immersion-day)
│   │   ├── java-ai-agents.sh             # Java-AI-Agents workshop setup (same as base)
│   │   └── java-spring-ai-agents.sh      # Java-Spring-AI-Agents workshop setup (same as base)
│   ├── setup/                   # Infrastructure setup scripts
│   │   ├── eks.sh               # EKS cluster configuration
│   │   ├── monitoring.sh        # Prometheus + Grafana setup
│   │   ├── analysis.sh          # Thread dump + profiling analysis
│   │   └── deploy-spring-app.sh # Spring application deployment
│   ├── lib/                     # Common utilities
│   │   ├── common.sh            # Emoji logging, error handling
│   │   └── wait-for-resources.sh # EKS/RDS readiness checking
│   ├── cfn/                     # CloudFormation utilities
│   │   ├── generate.sh
│   │   └── sync.sh
│   └── cleanup/                 # Cleanup scripts
└── package.json                 # Build automation
```

## Components and Interfaces

### CDK Components

#### WorkshopStack
The main CDK stack that conditionally creates resources based on template type:

```java
public class WorkshopStack extends Stack {
    public WorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        String templateType = (String) this.getNode().tryGetContext("template.type");
        if (templateType == null) {
            templateType = "base"; // default
        }

        // Core infrastructure (always created)
        var vpc = new Vpc(this, "Vpc");
        var ide = new Ide(this, "Ide", ideProps);

        // java-on-aws-immersion-day and java-on-amazon-eks specific resources
        if ("java-on-aws-immersion-day".equals(templateType) || "java-on-amazon-eks".equals(templateType)) {
            new CodeBuild(this, "CodeBuild", codeBuildProps);
            var database = new Database(this, "Database", vpc.getVpc());
            var eks = new Eks(this, "Eks", eksProps);
            var performanceAnalysis = new PerformanceAnalysis(this, "PerformanceAnalysis", analysisProps);
            var unicorn = new Unicorn(this, "Unicorn", unicornProps);
        }
    }
}
```

#### Supported Template Types

| Template Type | Resources Created |
|---------------|-------------------|
| `base` | VPC, IDE |
| `java-ai-agents` | VPC, IDE (same as base) |
| `java-spring-ai-agents` | VPC, IDE (same as base) |
| `java-on-aws-immersion-day` | VPC, IDE, CodeBuild, Database, EKS, PerformanceAnalysis, Unicorn |
| `java-on-amazon-eks` | VPC, IDE, CodeBuild, Database, EKS, PerformanceAnalysis, Unicorn (same as java-on-aws-immersion-day) |

#### Reusable Constructs

**Vpc**: Creates VPC with appropriate subnets and networking configuration
**Ide**: Creates VS Code IDE environment with necessary permissions and security groups
**Eks**: Creates EKS cluster with Auto Mode, v1.34, native add-ons (Secrets Store CSI, Mountpoint S3 CSI, Pod Identity Agent), Access Entries for IDE instance role, and IDE security group integration
**Database**: Configures RDS Aurora PostgreSQL cluster with universal "workshop-" naming convention
**CodeBuild**: Creates CodeBuild project for AWS service-linked role creation
**Lambda**: Reusable construct for consistent Lambda function creation with inline Python code
**WorkshopBucket**: Creates shared S3 bucket and SSM parameter for workshop data (uses prefix)
**ThreadAnalysis**: Creates thread dump Lambda and API Gateway for thread analysis (uses prefix)
**JvmAnalysis**: Creates ECR repository and Pod Identity role for jvm-analysis-service (app-specific naming)
**Unicorn**: Creates ECR repository and IAM roles for workshop applications (uses unicorn* naming for workshop content compatibility)

#### CDK Construct Naming Convention

All CDK constructs follow a consistent naming pattern to ensure clean CloudFormation logical IDs:
- **Pattern**: `{ConstructName}{ResourceType}` (e.g., `IdePasswordSecret`, `DatabaseCluster`)
- **Avoid duplication**: Resource names within constructs should not repeat the construct type
- **Examples**:
  - ✅ `Secret.Builder.create(this, "PasswordSecret")` → `IdePasswordSecret`
  - ❌ `Secret.Builder.create(this, "IdePasswordSecret")` → `IdeIdePasswordSecret`

This convention eliminates CloudFormation logical ID duplication and ensures maintainable resource naming.

#### AWS Resource Naming Convention

All AWS resources follow a consistent prefix pattern for operational clarity. The prefix is defined as a simple String constant at the beginning of WorkshopStack constructor (defaults to "workshop").

**Configurable Prefix Pattern:**
```java
public class WorkshopStack extends Stack {
    public WorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        // Resource naming prefix - change this to customize all resource names
        String prefix = "workshop";

        // Configuration values - get template type from CDK context (build time)
        String templateType = ...

        // Pass prefix to all constructs
        var ide = new Ide(this, "Ide", Ide.IdeProps.builder()
            .prefix(prefix)
            .vpc(vpc.getVpc())
            .build());
    }
}
```

**Lambda Functions (with default "workshop" prefix):**
- `{prefix}-codebuild-start` - CodeBuild start trigger
- `{prefix}-codebuild-report` - CodeBuild completion handler
- `{prefix}-ide-prefixlist` - CloudFront prefix list lookup
- `{prefix}-ide-launcher` - EC2 instance launcher with failover
- `{prefix}-ide-password` - Password retrieval from Secrets Manager
- `{prefix}-database-setup` - Database schema initialization

**CodeBuild Projects:**
- `{prefix}-setup` - Workshop environment setup and service-linked role creation

**CloudWatch Log Groups:**
- `{prefix}-ide-bootstrap-{timestamp}` - IDE bootstrap logs with unique timestamps
- `/aws/lambda/{prefix}-*` - All Lambda function logs grouped by prefix
- `/aws/codebuild/{prefix}-setup` - CodeBuild execution logs

**Exceptions (app-specific naming):**
- **Unicorn construct**: Uses "unicorn*" naming for workshop application compatibility
- **JvmAnalysis construct**: Uses "jvm-analysis-*" naming for profiling service resources

**Constructs using prefix:**
- Vpc, Ide, CodeBuild, Database, Eks, WorkshopBucket, ThreadAnalysis

**Constructs with app-specific naming (no prefix):**
- Unicorn (unicorn*), JvmAnalysis (jvm-analysis-*)

**Usage:**
```bash
# Default prefix ("workshop")
npm run generate

# Custom prefix - edit WorkshopStack.java:
#   String prefix = "alice";
# Then regenerate:
npm run generate
```

This naming convention enables:
- **Easy filtering** in AWS Console and CLI using `{prefix}-*` patterns
- **Simple customization** by editing one string constant
- **Reusable templates** by regenerating with different prefix
- **Operational management** through consistent resource identification
- **Cost tracking** and monitoring of workshop-related resources
- **Automated cleanup** and maintenance scripts

### Lambda Function Architecture

#### Design Rationale
The new design uses **minimal Lambda functions** with inline Python source code for CloudFormation template compatibility:
- **Java CDK constructs** for infrastructure definition and type safety
- **Single inline Python Lambda** for EC2 instance launching with intelligent failover
- **EC2 User Data** for bootstrap processes instead of Lambda functions
- **Native CDK implementations** for simple operations (prefix lists, secrets)

#### Simplified Architecture
Instead of multiple Lambda functions, the new design uses:
1. **One launcher Lambda** with inline Python code for intelligent EC2 failover
2. **Native CDK features** for CloudFront prefix lists and Secrets Manager
3. **EC2 User Data scripts** for instance bootstrap

#### Lambda Function Naming & Mapping

**Concise Naming Scheme**:
- Instance-specific: `{instance-name}-{purpose}`
- Workshop-wide: `workshop-{purpose}`

| Old Function Name Pattern | New Implementation | New Function Name | Scope | Purpose |
|---------------------------|-------------------|-------------------|-------|---------|
| `{instance}-prefix-list-lambda` | **CDK Native** | N/A | N/A | Static CloudFront prefix list reference |
| `{instance}-instance-launcher` | **Inline Lambda** | `{instance}-launcher` | Instance | EC2 instance launching with intelligent failover |
| `{instance}-password-lambda` | **CDK Native** | N/A | N/A | Direct secret value reference |
| `{instance}-bootstrap-lambda` | **EC2 User Data** | N/A | N/A | Moved to EC2 User Data scripts |
| `unicornstore-db-setup-lambda` | **Setup Scripts** | N/A | N/A | Moved to workshop setup scripts |

#### External Resource Approach
The new design uses **external files** for all complex scripts and code, loaded via CDK for better maintainability while preserving CloudFormation template compatibility through inline code generation. This approach eliminates hard-to-maintain inline code blocks and provides a **reusable Lambda construct** for consistent function creation.

#### External Resource Organization
```
infra/cdk/src/main/resources/
├── lambda/
│   ├── ec2-launcher.py           # EC2 instance launching with multi-AZ/instance-type failover
│   ├── codebuild-start.py        # CodeBuild project starter for workshop setup
│   ├── codebuild-report.py       # CodeBuild completion reporter via EventBridge
│   ├── password-exporter.py      # Custom Resource for password output
│   ├── database-setup.py         # Database schema initialization
│   ├── cloudfront-prefix-lookup.py # CloudFront prefix list lookup
│   └── thread-dump-lambda.py     # Thread dump collection and AI analysis
├── userdata.sh                   # Minimal UserData script with CloudWatch logging
├── iam-policy-base.json          # Base template IAM policy (Allow *)
├── iam-policy-java-on-aws-immersion-day.json   # Java-on-AWS Immersion Day workshop IAM policy
├── iam-policy-java-on-amazon-eks.json          # Java-on-Amazon-EKS workshop IAM policy (same as java-on-aws-immersion-day)
├── iam-policy-java-ai-agents.json              # Java-AI-Agents workshop IAM policy (same as base)
├── iam-policy-java-spring-ai-agents.json       # Java-Spring-AI-Agents workshop IAM policy (same as base)
├── iam-policy-{workshop}.json    # Workshop-specific IAM policies (required for each template type)
└── unicorns.sql                  # Database schema SQL
```

#### Reusable Lambda Construct
```java
public class Lambda extends Construct {
    public Lambda(final Construct scope, final String id, final LambdaProps props) {
        super(scope, id);

        Function.Builder.create(this, "Function")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.lambda_handler")
            .code(Code.fromInline(loadFile(props.getSourceFile())))
            .timeout(props.getTimeout())
            .functionName(props.getFunctionName())
            .role(props.getRole())
            .build();
    }
}
```

#### Usage in IDE Construct
```java
// Create EC2 launcher Lambda using reusable construct
var launcherLambda = new Lambda(this, "LauncherLambda",
    Lambda.LambdaProps.builder()
        .sourceFile("/lambda/ec2-launcher.py")
        .functionName(instanceName + "-launcher")
        .timeout(Duration.minutes(5))
        .role(props.getLambdaRole())
        .build());

// Create User Data from external script with variable substitution
var userData = UserData.forLinux();
String bootstrapScript = loadFile("/ec2-userdata.sh")
    .replace("${stackName}", Aws.STACK_NAME)
    .replace("${awsRegion}", Aws.REGION)
    .replace("${idePassword}", ideSecretsManagerPassword.secretValueFromJson("password").unsafeUnwrap());
userData.addCommands(bootstrapScript.split("\n"));
```

### EKS-IDE Integration

#### Security Group Sharing
The EKS cluster integrates with the IDE environment through shared security groups and IAM roles:

```java
// In WorkshopStack.java
Eks eks = new Eks(this, "Eks", Eks.EksProps.builder()
    .vpc(vpc.getVpc())
    .ideInstanceRole(ideProps.getIdeRole())           // Share IDE IAM role for kubectl access
    .ideInternalSecurityGroup(ide.getIdeInternalSecurityGroup()) // Share security group for VPC communication
    .build());
```

#### Access Control Integration
- **IDE Instance Role**: The same IAM role used by the IDE instance is granted EKS cluster admin access via Access Entries
- **Security Group**: The IDE's internal security group is used by the EKS cluster for VPC communication
- **kubectl Context**: The IDE bootstrap scripts configure kubectl to access the EKS cluster using the shared credentials

This integration ensures seamless access from the IDE to the EKS cluster without additional authentication setup.

### Script Organization

#### Minimal UserData Architecture
The new architecture uses minimal UserData that downloads and executes a full bootstrap script, avoiding AWS UserData size limits:

```
infra/cdk/src/main/resources/
└── userdata.sh           # Minimal UserData script with CloudWatch logging

infra/scripts/ide/
├── functions.sh          # Shared helper functions (retry_command, install_with_version, log_info)
├── bootstrap.sh          # Full bootstrap orchestration (jq, Docker, AWS CLI, environment setup)
├── vscode.sh             # VS Code Server installation and configuration
├── code-editor.sh        # AWS Code Editor installation
├── tools.sh              # Base development tools (Java, Node.js, kubectl, etc.)
├── settings.sh           # IDE settings configuration
├── shell.sh              # Shell UX (zsh + oh-my-zsh + powerlevel10k)
└── shell-p10k.zsh        # Powerlevel10k configuration

infra/scripts/templates/
├── base.sh                       # Base template (empty placeholder)
├── java-on-aws-immersion-day.sh  # Java-on-AWS Immersion Day workshop post-deploy
├── java-on-amazon-eks.sh         # Java-on-Amazon-EKS workshop post-deploy (same as java-on-aws-immersion-day)
├── java-ai-agents.sh             # Java-AI-Agents workshop post-deploy (same as base)
└── java-spring-ai-agents.sh      # Java-Spring-AI-Agents workshop post-deploy (same as base)
```

#### Shared Functions Architecture
All IDE scripts source `functions.sh` for consistent helper functions:
- `retry_command(attempts, delay, fail_mode, tool_name, cmd)`: Retry with configurable failure handling
- `retry_critical(tool_name, cmd)`: Retry with exit on failure (5 attempts, 5s delay)
- `retry_optional(tool_name, cmd)`: Retry with warning on failure (continues execution)
- `install_with_version(tool_name, install_cmd, version_cmd, fail_mode)`: Install and log version
- `log_info(message)`: Timestamped logging
- `download_and_verify(url, output, description)`: Download with retry

#### Bootstrap Flow
```
userdata.sh → bootstrap.sh → {IDE_TYPE}.sh → tools.sh → templates/{TEMPLATE_TYPE}.sh
```

Where:
- `userdata.sh`: Minimal UserData script that clones repo and runs bootstrap.sh with CloudWatch logging
- `bootstrap.sh`: System setup (jq, Docker, AWS CLI), environment variables in `/etc/profile.d/workshop.sh`, calls IDE setup and template script
- `{IDE_TYPE}.sh`: IDE-specific setup (vscode.sh or code-editor.sh), sources functions.sh
- `tools.sh`: Base development tools installation (Java, Node.js, kubectl, Helm, etc.), sources functions.sh and workshop.sh
- `templates/{TEMPLATE_TYPE}.sh`: Workshop-specific post-deploy (EKS setup, monitoring, analysis)

#### Environment Variables
Scripts source `/etc/profile.d/workshop.sh` instead of re-fetching AWS variables. This file is created by bootstrap.sh and contains:
- `AWS_REGION`, `AWS_DEFAULT_REGION`: AWS region from instance metadata
- `ACCOUNT_ID`, `AWS_ACCOUNT_ID`: AWS account ID from STS
- `EC2_PRIVATE_IP`, `EC2_DOMAIN`, `EC2_URL`: Instance networking
- `IDE_DOMAIN`, `IDE_URL`, `IDE_PASSWORD`: IDE access
- `JAVA_HOME`, `M2_HOME`: Development tool paths

#### Workshop Orchestration Pattern
Workshop scripts follow a layered approach:
1. **Bootstrap Layer**: `bootstrap.sh` installs jq, Docker, AWS CLI, creates `/etc/profile.d/workshop.sh` with all environment variables
2. **IDE Layer**: `bootstrap.sh` calls IDE setup (`vscode.sh` or `code-editor.sh`) which sources `functions.sh`
3. **Tools Layer**: `tools.sh` sources `functions.sh` and `workshop.sh`, provides foundational development tools
4. **Workshop Layer**: Template scripts in `templates/` folder add workshop-specific setup (EKS, monitoring, analysis)
5. **Error Handling**: Each layer implements proper error handling via shared `functions.sh`
6. **Verification**: Final verification ensures all tools and services are operational

#### Configuration
- **Template Type**: Configurable via `TEMPLATE_TYPE` environment variable (defaults to `base`)
- **Git Branch**: Defined in code as `"main"`
- **VS Code Version**: Uses latest version by default

#### Environment Variables
**Input (CDK reads):**
- `TEMPLATE_TYPE` - determines template type (defaults to "base")

**Output (CDK passes to scripts):**
- `STACK_NAME` - AWS stack name
- `TEMPLATE_TYPE` - template type
- `GIT_BRANCH` - git branch (hardcoded to "main")
- `PREFIX` - resource naming prefix (defaults to "workshop")

**Created by bootstrap.sh in `/etc/profile.d/workshop.sh`:**
- `AWS_REGION`, `AWS_DEFAULT_REGION` - AWS region
- `ACCOUNT_ID`, `AWS_ACCOUNT_ID` - AWS account ID
- `EC2_PRIVATE_IP`, `EC2_DOMAIN`, `EC2_URL` - Instance networking
- `IDE_DOMAIN`, `IDE_URL`, `IDE_PASSWORD` - IDE access
- `JAVA_HOME`, `M2_HOME` - Development tool paths

#### Tool Version Management
The system uses a hybrid approach for tool versions:

**Pinned Versions (Renovate Managed):**
- Java: 25 (default, installs 8,17,21,25)
- Node.js: 20 (LTS)
- Maven: 3.9.11
- kubectl: 1.34.2
- Helm: 3.19.3 (v3.x for chart compatibility)
- eksctl: 0.220.0
- eks-node-viewer: 0.7.4
- Docker Compose: 2.40.2
- SOCI: 0.12.0
- yq: 4.49.2

**Latest Versions (Auto-updating):**
- VS Code: latest
- AWS SAM CLI: latest
- Session Manager Plugin: latest
- AWS CLI: latest
- CDK: latest (npm global)
- Artillery: latest (npm global)
- k9s: latest (webinstall.dev)
- e1s: latest (GitHub script)

**System Packages (Repository Latest):**
- jq, Docker, git, Caddy: latest available in package repositories

#### Script Architecture
Scripts are organized with shared helper functions and consistent error handling:

**Shared Functions (`functions.sh`):**
- Central location for all helper functions used across IDE scripts
- `retry_command()`: Configurable retry with attempts, delay, and failure mode
- `retry_critical()`: Retry with exit on failure (5 attempts, 5s delay)
- `retry_optional()`: Retry with warning on failure (continues execution)
- `install_with_version()`: Install tool and log version in consistent format
- `log_info()`: Timestamped logging
- `download_and_verify()`: Download with retry and verification

**Bootstrap Script (`bootstrap.sh`):**
- Sources functions.sh for shared helpers
- Installs jq and Docker before IDE setup (services inherit docker group)
- Creates `/etc/profile.d/workshop.sh` with all environment variables
- Standardized on `dnf` package manager
- Error handling with CloudFormation signaling

**VS Code Script (`vscode.sh`):**
- Sources functions.sh for shared helpers
- Helper functions eliminate repetitive `sudo -u ec2-user` patterns
- `setup_user_file()` function for clean file creation
- `run_as_user()` function for user command execution
- Uses latest VS Code version by default

**Tools Script (`tools.sh`):**
- Sources functions.sh and `/etc/profile.d/workshop.sh`
- Function-based organization by tool category
- Uses shared retry and install functions
- No redundant AWS variable fetching

### Build Automation

#### Template Generation
The build process generates one unified CloudFormation template and syncs it to workshop directories:

```json
{
  "scripts": {
    "generate": "./scripts/cfn/generate.sh",
    "sync": "./scripts/cfn/sync.sh"
  }
}
```

**scripts/cfn/generate.sh**:
```bash
#!/bin/bash
set -e

echo "🔧 Generating unified template..."

cd cdk
mvn clean package
cdk synth WorkshopStack --yaml --path-metadata false --version-reporting false > ../workshop-template.yaml
cd ..

echo "✅ Generated workshop-template.yaml"
```

**scripts/cfn/sync.sh**:
```bash
#!/bin/bash
set -e

WORKSHOPS=("ide" "java-on-aws-immersion-day" "java-on-amazon-eks" "java-ai-agents" "java-spring-ai-agents")

for workshop in "${WORKSHOPS[@]}"; do
  target_dir="../$workshop/static"

  if [[ -d "$target_dir" ]]; then
    # Copy CloudFormation template
    cp "workshop-template.yaml" "$target_dir/$workshop-stack.yaml"
    echo "✅ Synced workshop-template.yaml to $workshop/static/$workshop-stack.yaml"

    # Copy IAM policy from resources
    if [[ -f "cdk/src/main/resources/iam-policy.json" ]]; then
      cp "cdk/src/main/resources/iam-policy.json" "$target_dir/policy.json"
      echo "✅ Synced iam-policy.json to $workshop/static/policy.json"
    fi
  else
    echo "⚠️  Directory $target_dir not found, skipping sync for $workshop"
  fi
done

echo "🎉 All templates and policies synced successfully!"
```

## Data Models

### Workshop Configuration
```java
public class WorkshopConfig {
    private String workshopType;
    private boolean includeEks;
    private boolean includeDatabase;
    private boolean includeBedrock;
    private Map<String, String> environmentVariables;

    // Constructor, getters, setters
}
```

### Script Execution Context
```java
public class ScriptContext {
    private String stackName;
    private String workshopType;
    private String region;
    private Map<String, String> resourceIds;
    private List<String> setupSteps;

    // Constructor, getters, setters
}
```

### Build Configuration
```java
public class BuildConfig {
    private List<String> workshopTypes;
    private String outputDirectory;
    private Map<String, String> templateMappings;

    // Constructor, getters, setters
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Workshop Type Resource Mapping
*For any* workshop type, the CDK stack should create exactly the resources specified for that workshop type and no others
**Validates: Requirements 1.2**

### Property 2: Template Generation Consistency
*For any* workshop type, generating a CloudFormation template should produce a template containing only the resources appropriate for that workshop type
**Validates: Requirements 1.3**

### Property 3: Script Output Format Consistency
*For any* setup script execution, all output messages should follow the emoji-based logging format
**Validates: Requirements 2.3, 3.3**

### Property 4: Error Handling Consistency
*For any* error condition during setup, the system should halt execution and display detailed error information with troubleshooting guidance
**Validates: Requirements 2.4, 3.2**

### Property 5: Convention-Based Script Discovery
*For any* stack name, the system should find and execute the corresponding workshop script with matching name
**Validates: Requirements 3.1**

### Property 6: Timeout Handling
*For any* setup operation that exceeds timeout limits, the system should abort with clear timeout messages and suggested actions
**Validates: Requirements 3.4**

### Property 7: Service Verification
*For any* completed setup script, the system should verify that all critical services are operational
**Validates: Requirements 3.5**

### Property 8: Build Log Capture
*For any* CodeBuild failure, the system should capture full logs and provide build ID for support reference
**Validates: Requirements 3.6**

### Property 9: Resource Waiting Behavior
*For any* critical resource that is not ready, the system should wait with progress indicators up to defined timeout limits
**Validates: Requirements 3.7**

### Property 10: Template Generation Completeness
*For any* build process execution, all expected workshop-specific CloudFormation templates should be generated
**Validates: Requirements 4.1**

### Property 11: Template Distribution Accuracy
*For any* generated template, it should be copied to the correct workshop directory with matching name
**Validates: Requirements 4.2**

### Property 12: Build Error Reporting
*For any* template generation failure, the build process should halt and report specific errors
**Validates: Requirements 4.4**

### Property 13: Distribution Verification
*For any* template distribution, the system should verify successful copying to all target locations
**Validates: Requirements 4.5**

### Property 14: Migration Directory Safety
*For any* migration process, the new infra/ directory structure should be created without modifying any files in infrastructure/
**Validates: Requirements 5.1**

### Property 15: Base Stack Composition
*For any* base CDK stack implementation, it should contain exactly VPC, IDE, and CodeBuild resources
**Validates: Requirements 5.2**

### Property 16: Template Equivalence
*For any* migrated workshop type, the new template should produce equivalent infrastructure to the existing template
**Validates: Requirements 5.5**

### Property 17: Lambda Function Modularity
*For any* modular Lambda function, it should provide equivalent functionality to original functions while maintaining CloudFormation template compatibility through inline Python source code
**Validates: Requirements 5.8**

### Property 18: Database Naming Consistency
*For any* database resource created, it should use the "workshop-" prefix instead of workshop-specific naming
**Validates: Requirements 12.1, 12.2, 12.3, 12.4, 12.5, 12.6**

### Property 19: EKS Access Entry Configuration
*For any* EKS cluster created, it should include Access Entry for IDE instance role with cluster admin permissions
**Validates: Requirements 13.8**

### Property 20: Workshop Script Orchestration
*For any* java-on-aws workshop execution, it should first execute base.sh successfully before proceeding to EKS implementation
**Validates: Requirements 17.1, 17.2**

### Property 21: Workshop Error Handling
*For any* workshop orchestration error, the system should halt execution and provide clear error messages indicating which phase failed
**Validates: Requirements 17.3**

### Property 22: Workshop Verification
*For any* completed workshop setup, both base tools and EKS services should be verified as operational
**Validates: Requirements 17.4**

### Property 23: EKS Cluster Readiness Check
*For any* EKS setup script execution, it should wait until kubectl get ns command works successfully before proceeding with resource deployment
**Validates: Requirements 18.1**

### Property 24: Kubectl Context Configuration
*For any* EKS cluster setup, the system should update kubeconfig and add cluster to kubectl context
**Validates: Requirements 18.2**

### Property 25: Parallel Deployment Independence
*For any* EKS cluster and database creation, they should depend only on VPC and deploy in parallel without unnecessary dependencies
**Validates: Requirements 19.1, 19.2, 19.3**

### Property 26: Configurable Prefix Pattern
*For any* AWS resource created by Vpc, Ide, CodeBuild, Database, or Eks constructs, it should use the prefix string defined in WorkshopStack constructor for all resource names
**Validates: Requirements 22.1, 22.2, 22.3, 22.4, 22.5**

### Property 27: Prefix Exception for App-Specific Constructs
*For any* resource created by Unicorn or JvmAnalysis constructs, it should use its own naming convention independent of the WorkshopStack prefix
**Validates: Requirements 22.6, 22.7**

### Property 28: WorkshopBucket Shared Resources
*For any* WorkshopBucket construct, it should create S3 bucket and SSM parameter using the prefix pattern for shared resource discovery
**Validates: Requirements 23.1, 23.2, 23.3**

### Property 29: ThreadAnalysis Infrastructure Naming
*For any* ThreadAnalysis construct, it should use the prefix pattern for all Lambda, API Gateway, IAM role, and security group resources
**Validates: Requirements 24.1, 24.2, 24.3, 24.4, 24.5**

### Property 30: JvmAnalysis App-Specific Naming
*For any* JvmAnalysis construct, it should use "jvm-analysis-*" naming for ECR repository and Pod Identity role
**Validates: Requirements 25.1, 25.2, 25.3**

## Error Handling

### Script Error Handling Strategy
All setup scripts implement consistent error handling using bash error traps:

```bash
#!/bin/bash
set -e  # Exit on any error

handle_error() {
    local exit_code=$1
    local line_number=$2
    echo "❌ ERROR: Command failed with exit code $exit_code at line $line_number"
    echo "🔍 Check the logs above for details"
    echo "📞 Contact workshop support if this persists"
    exit $exit_code
}

trap 'handle_error $? $LINENO' ERR
```

### CDK Error Handling
CDK constructs implement validation and error reporting:

```java
public class WorkshopVpc extends Construct {
    public WorkshopVpc(final Construct scope, final String id) {
        super(scope, id);

        try {
            this.vpc = Vpc.Builder.create(this, "Vpc")
                .maxAzs(2)
                .natGateways(1)
                .build();
        } catch (Exception e) {
            System.err.println("Failed to create VPC: " + e.getMessage());
            throw new RuntimeException("VPC creation failed", e);
        }
    }
}
```

### Timeout Management
Operations implement explicit timeout handling:

```bash
echo "⏳ Waiting for EKS cluster (timeout: 20 minutes)..."
timeout 1200 bash -c 'while ! check_cluster; do sleep 10; done' || {
    echo "⏰ TIMEOUT: EKS cluster did not become ready within 20 minutes"
    echo "🔍 Check CloudFormation events for cluster creation issues"
    exit 1
}
```

## Testing Strategy

### Unit Testing Approach
Unit tests focus on specific components and their interactions:
- CDK construct validation
- Script parsing and execution logic
- Configuration validation
- Error handling scenarios

### Property-Based Testing Approach
Property-based tests verify universal properties across all inputs using **QuickCheck for Java** (or similar library):
- Template generation consistency across workshop types
- Script discovery and execution patterns
- Error handling behavior across different failure modes
- Resource creation patterns for different workshop configurations

Each property-based test runs a minimum of 100 iterations to ensure comprehensive coverage of the input space.

### Test Organization
- Unit tests: Verify specific examples and integration points
- Property tests: Verify universal correctness properties
- Integration tests: Validate end-to-end workshop deployment scenarios

### Property Test Implementation
Each property-based test is tagged with a comment referencing the design document property:

```java
/**
 * Feature: infra, Property 1: Workshop Type Resource Mapping
 */
@Property
void workshopTypeResourceMapping(@ForAll String workshopType) {
    // Test implementation
}
```


## ECR Repository Creation Templates

### Overview

ECR Repository Creation Templates enable automatic repository creation when images are pushed, eliminating the need for explicit repository definitions in CDK. This simplifies infrastructure management and ensures consistent repository settings across all auto-created repositories.

### Architecture

The ECR Create-on-Push feature uses a registry-level template that applies to all repositories:

```
┌─────────────────────────────────────────────────────────────┐
│                    ECR Private Registry                      │
├─────────────────────────────────────────────────────────────┤
│  Repository Creation Template (ROOT prefix)                  │
│  ├── Applied For: CREATE_ON_PUSH, REPLICATION               │
│  ├── Image Tag Mutability: MUTABLE                          │
│  ├── Lifecycle Policy: 1 day untagged, 10 recent tagged     │
│  └── Resource Tags: Environment=workshop, ManagedBy=ecr-... │
├─────────────────────────────────────────────────────────────┤
│  Auto-Created Repositories (on first push):                  │
│  ├── unicorn-store-spring                                   │
│  ├── jvm-analysis-service                                   │
│  └── {any-new-repo}                                         │
└─────────────────────────────────────────────────────────────┘
```

### EcrRegistry Construct

A new `EcrRegistry` construct manages the repository creation template:

```java
package sample.com.constructs;

import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.ecr.CfnRepositoryCreationTemplate;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

/**
 * EcrRegistry construct for ECR private registry settings.
 * Creates Repository Creation Template for automatic repository creation on push.
 * Uses prefix for resource naming consistency.
 */
public class EcrRegistry extends Construct {

    private final CfnRepositoryCreationTemplate repositoryCreationTemplate;

    public static class EcrRegistryProps {
        private String prefix = "workshop";

        public static Builder builder() { return new Builder(); }

        public static class Builder {
            private EcrRegistryProps props = new EcrRegistryProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public EcrRegistryProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
    }

    public EcrRegistry(final Construct scope, final String id, final EcrRegistryProps props) {
        super(scope, id);

        String prefix = props.getPrefix();

        // Lifecycle policy JSON - expires untagged after 1 day, keeps 10 recent tagged
        String lifecyclePolicyJson = """
            {
                "rules": [
                    {
                        "rulePriority": 1,
                        "description": "Expire untagged images after 1 day",
                        "selection": {
                            "tagStatus": "untagged",
                            "countType": "sinceImagePushed",
                            "countUnit": "days",
                            "countNumber": 1
                        },
                        "action": {
                            "type": "expire"
                        }
                    },
                    {
                        "rulePriority": 2,
                        "description": "Keep only 10 most recent tagged images",
                        "selection": {
                            "tagStatus": "tagged",
                            "tagPrefixList": ["latest", "v"],
                            "countType": "imageCountMoreThan",
                            "countNumber": 10
                        },
                        "action": {
                            "type": "expire"
                        }
                    }
                ]
            }
            """;

        // Create Repository Creation Template
        this.repositoryCreationTemplate = CfnRepositoryCreationTemplate.Builder.create(this, "Template")
            .prefix("ROOT")  // Applies to all repositories
            .appliedFor(List.of("CREATE_ON_PUSH", "REPLICATION"))
            .imageTagMutability("MUTABLE")
            .lifecyclePolicy(lifecyclePolicyJson)
            .resourceTags(List.of(
                CfnRepositoryCreationTemplate.TagProperty.builder()
                    .key("Environment")
                    .value(prefix)
                    .build(),
                CfnRepositoryCreationTemplate.TagProperty.builder()
                    .key("ManagedBy")
                    .value("ecr-create-on-push")
                    .build()
            ))
            .description("Auto-create repositories on push with lifecycle policies for " + prefix + " workshop")
            .build();
    }

    public CfnRepositoryCreationTemplate getRepositoryCreationTemplate() {
        return repositoryCreationTemplate;
    }
}
```

### Changes to Existing Constructs

#### Unicorn Construct (Updated)

Remove explicit ECR repository creation:

```java
// BEFORE: Explicit repository creation
this.unicornStoreSpringEcr = Repository.Builder.create(this, "UnicornStoreSpringEcr")
    .repositoryName("unicorn-store-spring")
    .imageScanOnPush(false)
    .removalPolicy(RemovalPolicy.DESTROY)
    .emptyOnDelete(true)
    .build();

// AFTER: Remove ECR repository - created automatically on push
// Repository will be created when image is pushed with:
// docker push {account}.dkr.ecr.{region}.amazonaws.com/unicorn-store-spring:latest
```

#### JvmAnalysis Construct (Updated)

Remove explicit ECR repository creation:

```java
// BEFORE: Explicit repository creation
this.jvmAnalysisEcr = Repository.Builder.create(this, "Ecr")
    .repositoryName("jvm-analysis-service")
    .removalPolicy(RemovalPolicy.DESTROY)
    .emptyOnDelete(true)
    .build();

// AFTER: Remove ECR repository - created automatically on push
// Repository will be created when image is pushed with:
// docker push {account}.dkr.ecr.{region}.amazonaws.com/jvm-analysis-service:latest
```

### WorkshopStack Integration

Add EcrRegistry to WorkshopStack for java-on-aws-immersion-day and java-on-amazon-eks templates:

```java
// In WorkshopStack.java
if ("java-on-aws-immersion-day".equals(templateType) || "java-on-amazon-eks".equals(templateType)) {
    // ECR Registry settings (Repository Creation Template for create-on-push)
    EcrRegistry ecrRegistry = new EcrRegistry(this, "EcrRegistry",
        EcrRegistry.EcrRegistryProps.builder()
            .prefix(prefix)
            .build());

    // ... other resources (Database, EKS, etc.)
}
```

### Benefits

| Aspect | Before (Explicit Repos) | After (Create-on-Push) |
|--------|------------------------|------------------------|
| New repo creation | Requires CDK deploy | Push and go |
| Lifecycle policies | Manual per-repo | Automatic via template |
| Consistent tagging | Manual | Automatic |
| CDK code complexity | Higher | Lower |
| Workshop flexibility | Limited | Self-service |

### Correctness Properties for ECR

#### Property 31: Repository Creation Template Configuration
*For any* deployed CDK stack with java-on-aws-immersion-day or java-on-amazon-eks template type, the ECR Registry should contain a Repository Creation Template with ROOT prefix and CREATE_ON_PUSH enabled
**Validates: Requirements 26.1, 26.2**

#### Property 32: Lifecycle Policy Application
*For any* repository created via Create-on-Push, the lifecycle policy should expire untagged images after 1 day and keep only 10 most recent tagged images
**Validates: Requirements 27.1, 27.2, 27.3**

#### Property 33: Resource Tag Consistency
*For any* repository created via Create-on-Push, it should have Environment and ManagedBy tags applied from the template
**Validates: Requirements 29.1, 29.2**

#### Property 34: Construct Simplification
*For any* Unicorn or JvmAnalysis construct, it should not create explicit ECR repositories when EcrRegistry is present
**Validates: Requirements 28.1, 28.2, 28.3**


### Correctness Properties for Shared Functions

#### Property 35: Shared Functions Sourcing
*For any* IDE script (bootstrap.sh, vscode.sh, code-editor.sh, tools.sh), it should source functions.sh for shared helper functions
**Validates: Requirements 30.1**

#### Property 36: Environment Variable Sourcing
*For any* script that needs AWS variables (AWS_REGION, ACCOUNT_ID), it should source /etc/profile.d/workshop.sh instead of re-fetching from metadata or API
**Validates: Requirements 30.4, 31.1, 31.2**

#### Property 37: Docker Installation Timing
*For any* bootstrap execution, Docker should be installed before IDE setup so that IDE services inherit docker group membership without requiring restart
**Validates: Requirements 30.5**

#### Property 38: Consistent Variable Naming
*For any* script referencing AWS region, it should use AWS_REGION variable name (not REGION) for consistency
**Validates: Requirements 31.1, 31.3**
