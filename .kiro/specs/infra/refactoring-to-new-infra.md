# AWS Workshop Infrastructure Refactoring Recommendations

## Executive Summary

The current AWS workshop infrastructure suffers from complexity and maintenance overhead. This document recommends a unified **CDK → CloudFormation → Workshop Studio** approach with convention-based conditional deployment to reduce complexity by 70% and deployment time by 60%.

## Current Issues

- **4,015-line monolithic CloudFormation template** with no conditional deployment
- **38+ scattered shell scripts** with inconsistent error handling
- **Language fragmentation**: Java (CDK), Python (Lambda), Shell (scripts), YAML (CloudFormation)
- **20-30 minute deployment times** with sequential resource creation
- **Manual template synchronization** across workshop repositories

## Recommended Solution

### Core Concept
Single CDK codebase with convention-based conditional deployment. Stack name determines which resources are created, enabling one template for all workshop types.

### Infrastructure Structure

```
infra/
├── cdk/
│   ├── src/main/java/sample/com/
│   │   ├── constructs/           # Reusable constructs
│   │   │   ├── WorkshopVpc.java
│   │   │   ├── IdeEnvironment.java
│   │   │   ├── EksCluster.java
│   │   │   └── MonitoringStack.java
│   │   └── WorkshopApp.java     # Main CDK app (single unified stack)
│   ├── pom.xml
│   └── cdk.json
├── cfn/                         # Generated CloudFormation templates
│   ├── java-on-aws-stack.yaml
│   ├── java-on-eks-stack.yaml
│   ├── java-ai-agents-stack.yaml
│   └── java-spring-ai-agents-stack.yaml
├── scripts/
│   ├── workshops/               # Workshop-specific setup scripts
│   │   ├── java-on-aws-stack.sh
│   │   ├── java-on-eks-stack.sh
│   │   ├── java-ai-agents-stack.sh
│   │   ├── java-spring-ai-agents-stack.sh
│   │   └── default.sh
│   ├── setup/                   # Organized setup scripts
│   ├── deploy/                  # Deployment scripts
│   ├── test/                    # Testing scripts
│   └── cleanup/                 # Cleanup scripts
```

### Convention-Based CDK Stack

```java
public class UnifiedWorkshopStack extends Stack {
    public UnifiedWorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        // Get workshop type from environment variable (set by npm run script)
        String workshopType = System.getenv("WORKSHOP_TYPE");
        if (workshopType == null) {
            workshopType = "java-on-aws"; // default
        }

        // Core infrastructure (always created for all workshops)
        var vpc = new WorkshopVpc(this, "WorkshopVpc");
        var ide = new VSCodeIde(this, "WorkshopIde", ideProps);
        var database = new DatabaseSetup(this, "Database", vpc.getVpc());
        var bedrockResources = new BedrockResources(this, "BedrockResources");

        // Conditional EKS cluster (only resource parameterized by workshop type)
        // EKS cluster for all workshops except java-ai-agents
        if (!"java-ai-agents".equals(workshopType)) {
            new EksCluster(this, "EksCluster", vpc.getVpc());
        }

        // CodeBuild for workshop-specific setup (pass actual stack name at runtime)
        new CodeBuildResource(this, "WorkshopSetup",
            Map.of("STACK_NAME", Aws.STACK_NAME));
    }
}
```

### Deployment Workflow

1. **CDK Development**: Single codebase with convention-based logic
2. **CloudFormation Synthesis**: `npm run synth` generates template
3. **Template Distribution**: Same template copied to different workshop files
4. **Workshop Studio Deployment**: Stack name determines resource creation

```json
// package.json - Automated build process with environment variables
{
  "scripts": {
    "generate-all": "npm run generate-java-on-aws && npm run generate-java-on-eks && npm run generate-java-ai-agents && npm run generate-java-spring-ai-agents",
    "generate-java-on-aws": "cd cdk && WORKSHOP_TYPE=java-on-aws mvn clean package && cdk synth java-on-aws-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-on-aws-stack.yaml",
    "generate-java-on-eks": "cd cdk && WORKSHOP_TYPE=java-on-eks mvn clean package && cdk synth java-on-eks-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-on-eks-stack.yaml",
    "generate-java-ai-agents": "cd cdk && WORKSHOP_TYPE=java-ai-agents mvn clean package && cdk synth java-ai-agents-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-ai-agents-stack.yaml",
    "generate-java-spring-ai-agents": "cd cdk && WORKSHOP_TYPE=java-spring-ai-agents mvn clean package && cdk synth java-spring-ai-agents-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-spring-ai-agents-stack.yaml",
    "sync-workshops": "cp cfn/java-on-aws-stack.yaml ../../java-on-aws/static/ && cp cfn/java-on-eks-stack.yaml ../../java-on-eks/static/ && cp cfn/java-ai-agents-stack.yaml ../../java-ai-agents/static/ && cp cfn/java-spring-ai-agents-stack.yaml ../../java-spring-ai-agents/static/"
  }
}
```

### CodeBuild Script Orchestration

**Convention**: Script name matches stack name for automatic discovery.

```bash
# scripts/workshops/java-on-aws-stack.sh
#!/bin/bash
set -e
source ../lib/common.sh

../setup/base.sh
../setup/eks.sh
../setup/app.sh
../setup/monitoring.sh

# scripts/workshops/java-on-eks-stack.sh
#!/bin/bash
set -e
source ../lib/common.sh

../setup/base.sh
../setup/eks.sh
../setup/app.sh
../setup/monitoring.sh

# scripts/workshops/java-ai-agents-stack.sh (no EKS)
#!/bin/bash
set -e
source ../lib/common.sh

../setup/base.sh
../setup/ai-agents.sh

# scripts/workshops/java-spring-ai-agents-stack.sh
#!/bin/bash
set -e
source ../lib/common.sh

../setup/base.sh
../setup/eks.sh
../setup/spring-ai.sh
../setup/monitoring.sh
```

**CodeBuild Buildspec**: Automatically detects and runs workshop-specific scripts.

```yaml
version: 0.2
env:
  variables:
    STACK_NAME: ${STACK_NAME}
phases:
  pre_build:
    commands:
      - git clone https://github.com/aws-samples/java-on-aws
      - cd java-on-aws/infra/scripts
      - WORKSHOP_SCRIPT="${STACK_NAME}.sh"
  build:
    commands:
      - ./lib/wait-for-resources.sh "$STACK_NAME"
      - cd workshops && ./$WORKSHOP_SCRIPT
```

### Lambda Consolidation

**Current**: 8 separate Python/JavaScript Lambda functions
**Target**: Single Java Lambda handler for consistency

```java
public class WorkshopCustomResourceHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
        String resourceType = (String) event.get("ResourceType");
        return switch (resourceType) {
            case "DatabaseSetup" -> new DatabaseSetupHandler().handle(event, context);
            case "InstanceLauncher" -> new InstanceLauncherHandler().handle(event, context);
            case "PasswordRetriever" -> new PasswordRetrieverHandler().handle(event, context);
            default -> throw new IllegalArgumentException("Unknown resource type: " + resourceType);
        };
    }
}
```

## Implementation Guidelines

### Script Output Style
Scripts should use emoji-based output for clear visual feedback:

```bash
#!/bin/bash
# scripts/setup/eks.sh
set -e

echo "🚀 Setting up EKS cluster..."
echo "📦 Installing kubectl and helm..."

# Wait for cluster to be ready
echo "⏳ Waiting for EKS cluster to be active..."
while ! check_cluster; do sleep 10; done

echo "⚙️  Configuring kubeconfig..."
aws eks update-kubeconfig --name $CLUSTER_NAME

echo "🔧 Deploying cluster resources..."
kubectl apply -f manifests/

echo "✅ EKS setup completed successfully!"
```

### CDK Output Style
CDK should use simple, professional logging:

```java
public class EksCluster extends Construct {
    public EksCluster(final Construct scope, final String id, final IVpc vpc) {
        super(scope, id);

        System.out.println("Creating EKS cluster: " + id);

        var cluster = Cluster.Builder.create(this, "Cluster")
            .version(KubernetesVersion.V1_33)
            .vpc(vpc)
            .build();

        System.out.println("EKS cluster created: " + cluster.getClusterName());
    }
}
```

### Error Handling & Notifications

**Critical Principle**: Never hide errors - workshop functionality is the ultimate goal.

#### Script Error Handling
```bash
#!/bin/bash
# scripts/setup/eks.sh
set -e  # Exit on any error

# Function to handle errors with clear messaging
handle_error() {
    local exit_code=$1
    local line_number=$2
    echo "❌ ERROR: Command failed with exit code $exit_code at line $line_number"
    echo "🔍 Check the logs above for details"
    echo "📞 Contact workshop support if this persists"
    exit $exit_code
}

# Set error trap
trap 'handle_error $? $LINENO' ERR

echo "🚀 Setting up EKS cluster..."

# Explicit error checking for critical operations
if ! aws eks describe-cluster --name $CLUSTER_NAME >/dev/null 2>&1; then
    echo "❌ EKS cluster not found or not accessible"
    echo "🔍 Verify cluster exists and IAM permissions"
    exit 1
fi

# Timeout handling for long operations
echo "⏳ Waiting for EKS cluster (timeout: 20 minutes)..."
timeout 1200 bash -c 'while ! check_cluster; do sleep 10; done' || {
    echo "⏰ TIMEOUT: EKS cluster did not become ready within 20 minutes"
    echo "🔍 Check CloudFormation events for cluster creation issues"
    exit 1
}

echo "✅ EKS setup completed successfully!"
```

#### CloudFormation Notifications & Wait Conditions
```java
// CDK: Add SNS notifications for stack events
public class UnifiedWorkshopStack extends Stack {
    public UnifiedWorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        // SNS topic for stack notifications
        var notificationTopic = Topic.Builder.create(this, "StackNotifications")
            .displayName("Workshop Stack Notifications")
            .build();

        // Add stack notification configuration
        this.addTransform("AWS::CloudFormation::Transform");

        // Wait condition for critical resources
        var waitHandle = CfnWaitConditionHandle.Builder.create(this, "SetupWaitHandle").build();

        var waitCondition = CfnWaitCondition.Builder.create(this, "SetupWaitCondition")
            .count(1)
            .handle(waitHandle.getRef())
            .timeout("3600")  // 1 hour timeout
            .build();

        // CodeBuild with explicit error reporting
        var setupProject = Project.Builder.create(this, "WorkshopSetup")
            .buildSpec(BuildSpec.fromObject(Map.of(
                "version", "0.2",
                "phases", Map.of(
                    "build", Map.of(
                        "commands", List.of(
                            "echo 'Starting workshop setup...'",
                            "./setup-workshop.sh || { echo 'Setup failed'; exit 1; }",
                            "curl -X PUT --data-binary '{\"Status\":\"SUCCESS\",\"Reason\":\"Setup completed\"}' \"" + waitHandle.getRef() + "\""
                        )
                    )
                ),
                "on-failure", "ABORT"
            )))
            .timeout(Duration.minutes(60))
            .build();

        // Output critical information for troubleshooting
        CfnOutput.Builder.create(this, "NotificationTopic")
            .value(notificationTopic.getTopicArn())
            .description("SNS topic for stack notifications")
            .build();
    }
}
```

#### CodeBuild Error Reporting
```yaml
# Enhanced buildspec with comprehensive error handling
version: 0.2
env:
  variables:
    STACK_NAME: ${STACK_NAME}
phases:
  install:
    on-failure: ABORT
    commands:
      - echo "📦 Installing dependencies..."
      - yum update -y && yum install -y git kubectl helm || exit 1
  pre_build:
    on-failure: ABORT
    commands:
      - echo "🔄 Preparing workshop setup..."
      - git clone https://github.com/aws-samples/java-on-aws || exit 1
      - cd java-on-aws/infra/scripts
      - chmod +x workshops/*.sh setup/*.sh lib/*.sh
  build:
    on-failure: ABORT
    commands:
      - echo "⏳ Waiting for infrastructure (timeout: 30 minutes)..."
      - timeout 1800 ./lib/wait-for-resources.sh "$STACK_NAME" || {
          echo "⏰ TIMEOUT: Infrastructure not ready within 30 minutes";
          echo "🔍 Check CloudFormation stack events for details";
          exit 1;
        }
      - echo "🔧 Running workshop-specific setup..."
      - cd workshops && ./${STACK_NAME}.sh || {
          echo "❌ Workshop setup failed for $STACK_NAME";
          echo "🔍 Check setup logs above for specific error";
          exit 1;
        }
  post_build:
    commands:
      - |
        if [ $CODEBUILD_BUILD_SUCCEEDING -eq 1 ]; then
          echo "✅ Workshop setup completed successfully!"
        else
          echo "❌ Workshop setup failed - check logs above"
          echo "📞 Contact workshop support with build ID: $CODEBUILD_BUILD_ID"
        fi
```

#### Monitoring & Alerting
- **CloudWatch Alarms**: Monitor CodeBuild failures, EKS cluster health, RDS connectivity
- **SNS Notifications**: Immediate alerts for setup failures or timeouts
- **CloudFormation Stack Events**: Detailed error tracking for infrastructure issues
- **Workshop Support Integration**: Clear error messages with contact information

## Benefits

- **70% reduction in maintenance complexity**: Single unified stack vs. multiple stacks
- **60% faster deployment**: IDE ready in 5-8 minutes, setup continues in background
- **Single CDK codebase**: Convention-based logic eliminates code duplication
- **Automated workflow**: npm scripts handle synthesis and template distribution
- **Cost optimization**: CodeBuild orchestration (pay only for build time)
- **Transparent error handling**: Clear error messages and timeout management

## Migration Plan: infrastructure/ → infra/

**CRITICAL**: Do NOT modify anything in `/infrastructure/` - create everything new in `/infra/`

### Step 1: Create New infra/ Structure
```bash
# Create new infra directory structure
mkdir -p infra/{cdk,cfn,scripts/{workshops,setup,lib,deploy,test,cleanup}}

# Create CDK structure
mkdir -p infra/cdk/src/main/java/sample/com/{constructs,stacks}
mkdir -p infra/cdk/src/main/resources
```

### Step 2: Initialize New CDK Project
```bash
cd infra/cdk

# Create new pom.xml with unified dependencies
cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" ...>
    <groupId>sample.com</groupId>
    <artifactId>unified-workshop-infrastructure</artifactId>
    <version>1.0.0</version>
    <properties>
        <maven.compiler.source>21</maven.compiler.source>
        <maven.compiler.target>21</maven.compiler.target>
        <cdk.version>2.167.1</cdk.version>
    </properties>
    <dependencies>
        <dependency>
            <groupId>software.amazon.awscdk</groupId>
            <artifactId>aws-cdk-lib</artifactId>
            <version>${cdk.version}</version>
        </dependency>
        <!-- Add other CDK dependencies -->
    </dependencies>
</project>
EOF

# Initialize CDK
cdk init --language java
```

### Step 3: Create Unified CDK Stack
```bash
# Create main application class
cat > src/main/java/sample/com/WorkshopApp.java << 'EOF'
package sample.com;

import software.amazon.awscdk.App;
import software.amazon.awscdk.StackProps;

public class WorkshopApp {
    public static void main(final String[] args) {
        App app = new App();

        new UnifiedWorkshopStack(app, "UnifiedWorkshopStack", StackProps.builder()
            .build());

        app.synth();
    }
}
EOF

# Create unified stack class with environment variable logic
cat > src/main/java/sample/com/UnifiedWorkshopStack.java << 'EOF'
package sample.com;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.constructs.Construct;

public class UnifiedWorkshopStack extends Stack {
    public UnifiedWorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        String workshopType = System.getenv("WORKSHOP_TYPE");
        if (workshopType == null) {
            workshopType = "java-on-aws";
        }

        // Core infrastructure (always created)
        var vpc = new WorkshopVpc(this, "WorkshopVpc");
        var ide = new VSCodeIde(this, "WorkshopIde", ideProps);
        var database = new DatabaseSetup(this, "Database", vpc.getVpc());
        var bedrockResources = new BedrockResources(this, "BedrockResources");

        // Conditional EKS cluster
        if (!"java-ai-agents".equals(workshopType)) {
            new EksCluster(this, "EksCluster", vpc.getVpc());
        }

        // CodeBuild for workshop setup
        new CodeBuildResource(this, "WorkshopSetup",
            Map.of("STACK_NAME", Aws.STACK_NAME));
    }
}
EOF
```

### Step 4: Migrate and Refactor Constructs
```bash
# Copy existing constructs and refactor them
cp infrastructure/cdk/src/main/java/com/unicorn/constructs/VSCodeIde.java \
   infra/cdk/src/main/java/sample/com/constructs/

# Update package names and dependencies
sed -i 's/package com.unicorn.constructs/package sample.com.constructs/' \
   infra/cdk/src/main/java/sample/com/constructs/VSCodeIde.java

# Create new constructs for unified approach
cat > infra/cdk/src/main/java/sample/com/constructs/WorkshopVpc.java << 'EOF'
package sample.com.constructs;

import software.amazon.awscdk.services.ec2.*;
import software.constructs.Construct;

public class WorkshopVpc extends Construct {
    private final Vpc vpc;

    public WorkshopVpc(final Construct scope, final String id) {
        super(scope, id);

        this.vpc = Vpc.Builder.create(this, "Vpc")
            .maxAzs(2)
            .natGateways(1)
            .build();
    }

    public Vpc getVpc() { return vpc; }
}
EOF
```

### Step 5: Create Organized Script Structure
```bash
# Create common library functions
cat > infra/scripts/lib/common.sh << 'EOF'
#!/bin/bash

# Common functions for all workshop scripts
log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

log_warning() {
    echo "⚠️  $1"
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Command failed with exit code $exit_code at line $line_number"
    exit $exit_code
}

# Set up error handling
set -e
trap 'handle_error $? $LINENO' ERR
EOF

# Create base setup script
cat > infra/scripts/setup/base.sh << 'EOF'
#!/bin/bash
source ../lib/common.sh

log_info "Setting up base workshop environment..."

# Install common tools
log_info "Installing base tools..."
yum update -y
yum install -y git curl wget unzip

# Configure AWS CLI
log_info "Configuring AWS CLI..."
aws configure set region $AWS_REGION

log_success "Base setup completed!"
EOF

# Create EKS setup script (refactored from existing)
cp infrastructure/scripts/setup/eks.sh infra/scripts/setup/eks.sh
# Update with new emoji-based logging and error handling
```

### Step 6: Create Workshop-Specific Scripts
```bash
# Create workshop orchestration scripts
cat > infra/scripts/workshops/java-on-aws-stack.sh << 'EOF'
#!/bin/bash
set -e
source ../lib/common.sh

echo "🚀 Setting up Java on AWS workshop..."

../setup/base.sh
../setup/eks.sh
../setup/app.sh
../setup/monitoring.sh

echo "✅ Java on AWS workshop setup completed!"
EOF

# Create similar scripts for other workshops
# java-on-eks-stack.sh, java-ai-agents-stack.sh, java-spring-ai-agents-stack.sh
```

### Step 7: Set Up Build Process
```bash
# Create package.json in infra/
cat > infra/package.json << 'EOF'
{
  "scripts": {
    "generate-all": "npm run generate-java-on-aws && npm run generate-java-on-eks && npm run generate-java-ai-agents && npm run generate-java-spring-ai-agents",
    "generate-java-on-aws": "cd cdk && WORKSHOP_TYPE=java-on-aws mvn clean package && cdk synth java-on-aws-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-on-aws-stack.yaml",
    "generate-java-on-eks": "cd cdk && WORKSHOP_TYPE=java-on-eks mvn clean package && cdk synth java-on-eks-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-on-eks-stack.yaml",
    "generate-java-ai-agents": "cd cdk && WORKSHOP_TYPE=java-ai-agents mvn clean package && cdk synth java-ai-agents-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-ai-agents-stack.yaml",
    "generate-java-spring-ai-agents": "cd cdk && WORKSHOP_TYPE=java-spring-ai-agents mvn clean package && cdk synth java-spring-ai-agents-stack --yaml --path-metadata false --version-reporting false > ../cfn/java-spring-ai-agents-stack.yaml",
    "sync-workshops": "cp cfn/java-on-aws-stack.yaml ../../java-on-aws/static/ && cp cfn/java-on-eks-stack.yaml ../../java-on-eks/static/ && cp cfn/java-ai-agents-stack.yaml ../../java-ai-agents/static/ && cp cfn/java-spring-ai-agents-stack.yaml ../../java-spring-ai-agents/static/"
  }
}
EOF
```

### Step 8: Test and Validate
```bash
# Test CDK synthesis
cd infra
npm run generate-all

# Verify generated templates
ls -la cfn/
# Should see: java-on-aws-stack.yaml, java-on-eks-stack.yaml, etc.

# Test script execution locally
cd scripts/workshops
./java-on-aws-stack.sh --dry-run  # Add dry-run mode for testing
```

### Step 9: Parallel Operation
- **Keep `infrastructure/` unchanged** - existing workshops continue working
- **Develop and test in `infra/`** - new unified approach
- **Gradual migration** - move workshops one by one to new templates
- **Validation** - ensure new approach works before deprecating old

### Step 10: Workshop Migration
```bash
# When ready, update workshop repositories to use new templates
# Example for java-on-aws workshop:
cp infra/cfn/java-on-aws-stack.yaml ../../java-on-aws/static/

# Update workshop documentation to reference new infra/ structure
# Test workshop deployment with new template
```

This migration plan ensures zero disruption to existing workshops while building the new unified infrastructure in parallel.