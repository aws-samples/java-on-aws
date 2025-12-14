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
│   │   │   └── Roles.java
│   │   ├── WorkshopStack.java    # Main stack
│   │   └── WorkshopApp.java      # Main CDK application
│   ├── src/main/resources/
│   │   └── ec2-userdata.sh       # Minimal UserData script (embedded in CDK)
│   ├── pom.xml
│   └── cdk.json
├── workshop-template.yaml       # Generated unified CloudFormation template
├── scripts/
│   ├── ide/                     # Modular IDE and workshop scripts
│   │   ├── vscode.sh            # VS Code installation and configuration
│   │   ├── base.sh              # Base development tools
│   │   ├── java-on-aws.sh       # Java-on-AWS workshop setup
│   │   ├── java-on-eks.sh       # Java-on-EKS workshop setup
│   │   └── java-ai-agents.sh    # Java AI Agents workshop setup
│   ├── lib/                     # Common utilities (actively used)
│   │   ├── common.sh            # Emoji logging, error handling (used by generate.sh, sync.sh)
│   │   └── wait-for-resources.sh # EKS/RDS readiness checking (used by setup scripts)
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

        String templateType = System.getenv("TEMPLATE_TYPE");
        if (templateType == null) {
            templateType = "base"; // default
        }

        // Core infrastructure (always created)
        var vpc = new Vpc(this, "Vpc");
        var ide = new Ide(this, "Ide", vpc.getVpc());

        // Custom roles and database only for non-base templates
        if (!"base".equals(templateType)) {
            var roles = new Roles(this, "Roles");
            var database = new Database(this, "Database", vpc.getVpc());
        }

        // CodeBuild for service-linked role creation
        new CodeBuild(this, "CodeBuild",
            Map.of("STACK_NAME", Aws.STACK_NAME, "TEMPLATE_TYPE", templateType));
    }
}
```

#### Reusable Constructs

**Vpc**: Creates VPC with appropriate subnets and networking configuration
**Ide**: Creates VS Code IDE environment with necessary permissions
**Eks**: Creates EKS cluster with Auto Mode, v1.34, native add-ons (Secrets Store CSI, Mountpoint S3 CSI, Pod Identity Agent), and Access Entries
**Database**: Configures RDS Aurora PostgreSQL cluster with universal "workshop-" naming convention
**CodeBuild**: Creates CodeBuild project for AWS service-linked role creation
**Roles**: Creates IAM roles and policies for workshop resources

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
│   ├── ec2-launcher.py      # EC2 instance launching with multi-AZ/instance-type failover
│   ├── codebuild-start.py   # CodeBuild project starter for workshop setup
│   └── codebuild-report.py  # CodeBuild completion reporter via EventBridge
└── ec2-userdata.sh          # Minimal UserData script (2.4KB) with CloudWatch logging
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

### Script Organization

#### Minimal UserData Architecture
The new architecture uses minimal UserData (2.4KB) that downloads and executes a full bootstrap script, avoiding AWS UserData size limits:

```
infra/cdk/src/main/resources/
└── ec2-userdata.sh       # Minimal UserData script (2.4KB)

infra/scripts/ide/
├── bootstrap.sh          # Full bootstrap script (3.8KB)
├── vscode.sh             # VS Code installation and configuration
├── base.sh               # Base development tools (foundational for all workshops)
├── java-on-aws.sh        # calls base.sh + EKS/DB setup
├── java-on-eks.sh        # calls base.sh + EKS setup
└── java-ai-agents.sh     # calls base.sh + AI setup
```

#### Bootstrap Flow
```
ec2-userdata.sh → bootstrap.sh → vscode.sh → {workshop}.sh
```

Where:
- `ec2-userdata.sh`: Minimal UserData script that downloads and runs bootstrap.sh with fallback URLs
- `bootstrap.sh`: Full system setup, CloudWatch, environment variables, git clone, calls vscode.sh and template script
- `vscode.sh`: Complete VS Code IDE setup (code-server, Caddy, configuration)
- `base.sh`: Base development tools (for base template type)
- `java-on-aws.sh`: Calls base.sh + EKS implementation (cluster setup, add-ons, storage classes)
- Future template scripts will be added to `/ide` folder as needed

#### Workshop Orchestration Pattern
Workshop scripts follow a layered approach:
1. **Base Layer**: `base.sh` provides foundational development tools (Java, Node.js, kubectl, Helm, etc.)
2. **Workshop Layer**: Workshop-specific scripts (e.g., `java-on-aws.sh`) call base.sh then add specialized setup
3. **Error Handling**: Each layer implements proper error handling and progress feedback
4. **Verification**: Final verification ensures all tools and services are operational

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
Scripts are organized with helper functions and consistent error handling:

**Bootstrap Script (`ide-bootstrap.sh`):**
- Standardized on `dnf` package manager
- Added error handling for critical operations (AWS CLI, git clone, CloudFront)
- Improved logging and comments

**VS Code Script (`vscode.sh`):**
- Helper functions eliminate repetitive `sudo -u ec2-user` patterns
- `setup_user_file()` function for clean file creation
- `run_as_user()` function for user command execution
- Uses latest VS Code version by default

**IDE Script (`ide.sh`):**
- Function-based organization by tool category
- Comprehensive logging with timestamps (`log_info()`)
- Error handling and download verification (`handle_error()`, `download_and_verify()`)
- Consistent output handling and cleanup
- Removed redundant operations (multiple `java -version` calls)

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

WORKSHOPS=("ide" "java-on-aws" "java-on-eks" "java-ai-agents" "java-spring-ai-agents")

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
*For any* EKS cluster created, it should include Access Entry for WSParticipantRole with cluster admin permissions
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