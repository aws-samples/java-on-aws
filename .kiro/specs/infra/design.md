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
│   │   │   └── Roles.java
│   │   ├── stacks/
│   │   │   └── WorkshopStack.java
│   │   └── WorkshopApp.java     # Main CDK application
│   ├── pom.xml
│   └── cdk.json
├── cfn/                         # Generated CloudFormation templates
│   ├── ide.yaml
│   ├── java-on-aws.yaml
│   ├── java-on-eks.yaml
│   ├── java-ai-agents.yaml
│   └── java-spring-ai-agents.yaml
├── scripts/
│   ├── workshops/               # Workshop-specific orchestration scripts
│   │   ├── ide.sh
│   │   ├── java-on-aws.sh
│   │   ├── java-on-eks.sh
│   │   ├── java-ai-agents.sh
│   │   └── java-spring-ai-agents.sh
│   ├── setup/                   # Modular setup scripts
│   │   ├── base.sh
│   │   ├── eks.sh
│   │   ├── app.sh
│   │   ├── monitoring.sh
│   │   └── ai-agents.sh
│   ├── lib/                     # Common utilities
│   │   ├── common.sh
│   │   └── wait-for-resources.sh
│   ├── deploy/                  # Deployment utilities
│   ├── test/                    # Testing scripts
│   └── cleanup/                 # Cleanup scripts
└── package.json                 # Build automation
```

## Components and Interfaces

### CDK Components

#### WorkshopStack
The main CDK stack that conditionally creates resources based on workshop type:

```java
public class WorkshopStack extends Stack {
    public WorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        String workshopType = System.getenv("WORKSHOP_TYPE");
        if (workshopType == null) {
            workshopType = "ide"; // default
        }

        // Core infrastructure (always created)
        var roles = new Roles(this, "Roles");
        var vpc = new Vpc(this, "Vpc");
        var ide = new Ide(this, "Ide", vpc.getVpc(), roles);

        // Conditional resources based on workshop type
        if (!"ide".equals(workshopType) && !"java-ai-agents".equals(workshopType)) {
            new Eks(this, "Eks", vpc.getVpc(), roles);
        }

        if (!"ide".equals(workshopType)) {
            new Database(this, "Database", vpc.getVpc());
        }

        // CodeBuild for workshop setup
        new CodeBuild(this, "CodeBuild",
            Map.of("STACK_NAME", Aws.STACK_NAME, "WORKSHOP_TYPE", workshopType));
    }
}
```

#### Reusable Constructs

**Vpc**: Creates VPC with appropriate subnets and networking configuration
**Ide**: Creates VS Code IDE environment with necessary permissions
**Eks**: Creates EKS cluster with AutoMode
**Database**: Configures RDS instances and database schemas
**CodeBuild**: Creates CodeBuild project for workshop setup automation
**Roles**: Creates IAM roles and policies for workshop resources

### Script Organization

#### Convention-Based Script Discovery
Scripts are organized using a naming convention where the script name matches the stack name:
- `ide.sh` → executed for ide workshop type
- `java-on-aws.sh` → executed for java-on-aws workshop type
- `java-on-eks.sh` → executed for java-on-eks workshop type

#### Modular Setup Scripts
Common functionality is extracted into reusable modules:
- `base.sh`: Common tools and AWS CLI configuration
- `eks.sh`: EKS cluster configuration and kubectl setup
- `app.sh`: Application deployment and configuration
- `monitoring.sh`: Observability stack setup
- `ai-agents.sh`: AI-specific setup for agent workshops

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
cdk synth stack --yaml --path-metadata false --version-reporting false > ../cfn/stack.yaml
cd ..

echo "✅ Generated cfn/stack.yaml"
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
    cp "cfn/stack.yaml" "$target_dir/$workshop-stack.yaml"
    echo "✅ Synced stack.yaml to $workshop/static/$workshop-stack.yaml"

    # Copy IAM policy if it exists
    if [[ -f "policies/policy.json" ]]; then
      cp "policies/policy.json" "$target_dir/"
      echo "✅ Synced policy to $workshop/static/"
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

### Property 17: Lambda Function Consolidation
*For any* consolidated Lambda handler, it should provide equivalent functionality to all original Python/JavaScript functions
**Validates: Requirements 5.8**

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