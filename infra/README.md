# Workshop Infrastructure

CDK project for generating CloudFormation templates for AWS workshops. Uses a unified, convention-based approach with a single CDK codebase that generates different templates based on workshop type.

## Quick Start

```bash
# Generate all CloudFormation templates
npm run generate

# Sync templates to workshop directories
npm run sync
```

---

## Project Structure

```
infra/
├── cdk/                              # CDK Java project
│   ├── src/main/java/sample/com/
│   │   ├── WorkshopApp.java          # CDK application entry point
│   │   ├── WorkshopStack.java        # Main stack with conditional resources
│   │   └── constructs/               # Reusable CDK constructs
│   │       ├── Vpc.java              # VPC with 2 AZs, 1 NAT gateway
│   │       ├── Ide.java              # VS Code/Code Editor IDE environment
│   │       ├── Eks.java              # EKS v2 with Auto Mode
│   │       ├── Database.java         # Aurora PostgreSQL Serverless v2
│   │       ├── CodeBuild.java        # Service-linked role creation
│   │       ├── Lambda.java           # Reusable Lambda construct
│   │       ├── WorkshopBucket.java   # Shared S3 bucket + SSM parameter
│   │       ├── ThreadAnalysis.java   # Thread dump Lambda + API Gateway
│   │       ├── AiJvmAnalyzer.java    # Pod Identity for AI analyzer
│   │       ├── Unicorn.java          # EventBus + IAM roles for workshop apps
│   │       ├── EcrRegistry.java      # ECR create-on-push template
│   │       ├── EcsExpressService.java # ECS Express Mode service for AI agents
│   │       └── CfnPreDeleteCleanup.java  # Stack cleanup Lambda
│   ├── src/main/resources/
│   │   ├── userdata.sh               # EC2 UserData bootstrap script
│   │   ├── iam-policy.json           # Shared IAM policy
│   │   ├── unicorns.sql              # Database schema
│   │   └── lambda/                   # Python Lambda functions
│   │       ├── ec2-launcher.py       # EC2 instance launching with failover
│   │       ├── codebuild-start.py    # CodeBuild project starter
│   │       ├── codebuild-report.py   # CodeBuild completion reporter
│   │       ├── password-exporter.py  # Password Custom Resource
│   │       ├── database-setup.py     # Database schema initialization
│   │       ├── cloudfront-prefix-lookup.py
│   │       ├── thread-dump-lambda.py
│   │       └── cfn-pre-delete-cleanup.py
│   ├── pom.xml                       # Maven dependencies (CDK 2.233.0, Java 25)
│   └── cdk.json                      # CDK configuration
├── cfn/                              # Generated CloudFormation templates
│   ├── base-stack.yaml
│   ├── java-on-aws-immersion-day-stack.yaml
│   ├── java-on-amazon-eks-stack.yaml
│   └── java-spring-ai-agents-stack.yaml
├── scripts/
│   ├── ide/                          # IDE bootstrap scripts
│   │   ├── functions.sh              # Shared helpers (retry, logging)
│   │   ├── bootstrap.sh              # Main bootstrap orchestration
│   │   ├── vscode.sh                 # code-server installation
│   │   ├── code-editor.sh            # AWS Code Editor installation
│   │   ├── tools.sh                  # Development tools (Java, kubectl, etc.)
│   │   ├── settings.sh               # IDE settings configuration
│   │   ├── shell.sh                  # zsh + oh-my-zsh + powerlevel10k
│   │   └── shell-p10k.zsh            # Powerlevel10k config
│   ├── templates/                    # Workshop-specific post-deploy scripts
│   │   ├── base.sh
│   │   ├── java-on-aws-immersion-day.sh
│   │   ├── java-on-amazon-eks.sh
│   │   └── java-spring-ai-agents.sh
│   ├── setup/                        # Infrastructure setup scripts
│   │   ├── eks.sh                    # EKS cluster configuration
│   │   ├── monitoring.sh             # Prometheus + Grafana
│   │   ├── analysis.sh               # Thread dump + profiling
│   │   ├── unicorn-store-spring.sh   # Spring app deployment
│   │   └── java-spring-ai-agents/    # Spring AI agents setup
│   │       ├── build-and-push.sh     # Build and push images to ECR
│   │       └── Dockerfile            # Placeholder container image
│   ├── lib/                          # Common utilities
│   │   ├── common.sh                 # Emoji logging, error handling
│   │   └── wait-for-resources.sh     # EKS/RDS readiness checking
│   ├── cfn/                          # CloudFormation utilities
│   │   ├── generate.sh               # Template generation
│   │   └── sync.sh                   # Template distribution
│   ├── deploy/                       # Deployment scripts
│   ├── test/                         # Testing scripts
│   └── cleanup/                      # Cleanup scripts
└── package.json                      # npm scripts for build automation
```

## Template Types

| Template Type | Resources Created |
|---------------|-------------------|
| `base` | VPC, IDE |
| `java-on-aws-immersion-day` | VPC, IDE, CodeBuild, Database, EKS, WorkshopBucket, EcrRegistry, Unicorn, ECR (unicorn-store-spring), ThreadAnalysis, AiJvmAnalyzer |
| `java-on-amazon-eks` | Same as java-on-aws-immersion-day |
| `java-spring-ai-agents` | VPC, IDE, CodeBuild, Database, EKS, WorkshopBucket, EcrRegistry, Unicorn, 2x EcsExpressService (unicorn-spring-ai-agent, unicorn-store-spring) |

---

## Requirements

### Unified CDK Codebase

The infrastructure uses a single CDK codebase with convention-based conditional deployment. Template type is specified via CDK context at build time, and resources are conditionally created based on that type. The default template type is `base` which creates only VPC and IDE resources.

### Parallel Deployment

Infrastructure deployment maximizes parallelism for faster provisioning:
- VPC deploys first as the foundation
- EKS cluster and Database deploy in parallel (both depend only on VPC)
- IDE and CloudFront deploy in parallel with other resources
- CodeBuild waits for VPC before executing setup scripts

### Bootstrap Architecture

The IDE bootstrap uses a minimal UserData script that downloads and executes a full bootstrap from the repository. This avoids AWS UserData size limits while enabling modular script organization.

Bootstrap flow: `userdata.sh → bootstrap.sh → {IDE_TYPE}.sh → tools.sh → templates/{TEMPLATE_TYPE}.sh`

Scripts source `/etc/profile.d/workshop.sh` for AWS environment variables instead of re-fetching from metadata.

### Error Handling

All scripts implement consistent error handling:
- Error traps signal CloudFormation immediately on failure (no 30-minute timeouts)
- Emoji-based logging for visual feedback (✅ ❌ ⚠️ ℹ️)
- Retry logic with exponential backoff for network operations
- Clear error messages with line numbers for debugging

### Resource Naming

All AWS resources use a configurable prefix (default: `workshop`) following the pattern `{prefix}-{component}-{function}`:
- Lambda functions: `workshop-ide-launcher`
- Database: `workshop-db-cluster`, `workshop-db-writer`
- EKS: `workshop-eks`
- Secrets: `workshop-db-secret`, `workshop-db-password-secret`

Exceptions for app-specific compatibility:
- Unicorn construct uses `unicorn*` naming
- AiJvmAnalyzer uses `ai-jvm-analyzer-*` naming

### Multi-Instance Construct Support

The infrastructure supports multiple instances of certain constructs with unique, predictable naming:

#### Multi-Instance Capable Constructs
- **CodeBuild**: Uses `projectName` parameter for all resource naming
  - CodeBuild project: `{projectName}`
  - Lambda functions: `{projectName}-start`, `{projectName}-report`
  - EventBridge rules: Filtered by project name
- **EcsExpressService**: Uses `appName` parameter for all resource naming
  - ECS cluster: `{appName}`
  - ECS service: `{appName}`
  - CloudWatch log group: `/aws/ecs/{appName}`
- **Lambda**: Uses `functionName` parameter for function naming
  - Lambda function: `{functionName}`

#### Singleton Constructs
These constructs are designed as singletons and should only be instantiated once per stack:
- **Vpc**: Creates shared VPC infrastructure
- **Database**: Creates shared Aurora PostgreSQL cluster
- **Eks**: Creates shared EKS cluster
- **Unicorn**: Creates shared EventBus and IAM roles with hardcoded names
- **Ide**: Creates single IDE instance
- **WorkshopBucket**: Creates shared S3 bucket
- **EcrRegistry**: Sets account-wide ECR settings

#### Current Multi-Instance Usage
```java
// Two CodeBuild instances with unique project names
new CodeBuild(this, "CodeBuild",
    CodeBuildProps.builder().projectName("workshop-setup").build());
new CodeBuild(this, "PlaceholderImageBuild",
    CodeBuildProps.builder().projectName("workshop-placeholder-images").build());

// Two ECS services with unique app names
new EcsExpressService(this, "SpringAiAgent",
    EcsExpressServiceProps.builder().appName("unicorn-spring-ai-agent").build());
new EcsExpressService(this, "McpServer",
    EcsExpressServiceProps.builder().appName("unicorn-store-spring").build());
```

### Development Tools

The IDE includes comprehensive development tooling:
- Java: 8, 17, 21, 25 (configurable default)
- Node.js: 20 LTS via NVM
- Kubernetes: kubectl, Helm, eks-node-viewer, k9s, e1s
- Container: Docker, SOCI snapshotter
- AWS: SAM CLI, Session Manager Plugin, CDK

### IDE Configuration

VS Code/Code Editor is configured for distraction-free workshop experience:
- AI features disabled (Copilot, Agent panel, Amazon Q)
- Workspace trust disabled
- Terminal opens on startup
- Java, Docker, Kubernetes extensions pre-installed

---

## Design

### CDK Architecture

The CDK follows a **CDK → CloudFormation → Workshop Studio** workflow. `WorkshopStack` is the main stack that conditionally creates resources based on template type:

```java
public WorkshopStack(...) {
    String prefix = "workshop";
    String templateType = getContext("template.type"); // defaults to "base"

    boolean isImmersionDay = "java-on-aws-immersion-day".equals(templateType);
    boolean isEks = "java-on-amazon-eks".equals(templateType);
    boolean isSpringAi = "java-spring-ai-agents".equals(templateType);
    boolean isFullTemplate = isImmersionDay || isEks || isSpringAi;

    // Always created
    Vpc vpc = new Vpc(this, "Vpc", ...);
    Ide ide = new Ide(this, "Ide", ...);

    // Full template resources (all 3 workshop types)
    if (isFullTemplate) {
        new CodeBuild(...);
        Database database = new Database(...);
        Eks eks = new Eks(...);
        Unicorn unicorn = new Unicorn(...);  // EventBus, EKS/ECS roles, DB setup

        // java-on-aws-immersion-day & java-on-amazon-eks only
        if (isImmersionDay || isEks) {
            new Repository("unicorn-store-spring");  // ECR for manual deployment
            new ThreadAnalysis(...);
            new AiJvmAnalyzer(...);
        }

        // java-spring-ai-agents only
        if (isSpringAi) {
            new EcsExpressService("unicorn-spring-ai-agent", unicorn);  // ECR + ECS + ALB
            new EcsExpressService("unicorn-store-spring", unicorn);     // ECR + ECS + ALB
        }
    }
}
```

### CDK Construct Naming Convention

Constructs follow `{ConstructName}{ResourceType}` pattern for clean CloudFormation logical IDs:
- ✅ `Secret.Builder.create(this, "PasswordSecret")` → `IdePasswordSecret`
- ❌ `Secret.Builder.create(this, "IdePasswordSecret")` → `IdeIdePasswordSecret`

### EKS Configuration

EKS uses the v2 developer preview construct (`software.amazon.awscdk.services.eks.v2.alpha`) with:
- Auto Mode with `system` and `general-purpose` node pools
- Kubernetes version 1.34
- Access Entries authentication (not ConfigMap-based)
- IDE instance role granted cluster admin access
- All log types enabled (api, audit, authenticator, controllerManager, scheduler)

EKS Add-ons (AWS-native, no Helm charts):
- AWS Secrets Store CSI Driver (replaces External Secrets Operator)
- AWS Mountpoint S3 CSI Driver
- EKS Pod Identity Agent

Post-deployment setup (`scripts/setup/eks.sh`) deploys:
- GP3 StorageClass (encrypted, default)
- ALB IngressClass for Application Load Balancer
- Workshop NodePool (AMD, 4+ vCPU, 16+ GB RAM)

### Database Configuration

Aurora PostgreSQL Serverless v2 with universal naming:
- Cluster: `workshop-db-cluster`
- Instance: `workshop-db-writer`
- Database name: `workshop`
- Secrets: `workshop-db-secret`, `workshop-db-password-secret`
- Parameter Store: `workshop-db-connection-string`

### Secrets in Kubernetes

Database secrets are mounted as files via AWS Secrets Store CSI Driver. Spring Boot reads them using `configtree`:

```yaml
# SecretProviderClass defines which secrets to mount
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: unicorn-store-secrets
spec:
  provider: aws
  parameters:
    usePodIdentity: "true"
    objects: |
      - objectName: "workshop-db-secret"
        objectType: "secretsmanager"
        jmesPath:
          - path: "password"
            objectAlias: "spring.datasource.password"
          - path: "username"
            objectAlias: "spring.datasource.username"
      - objectName: "workshop-db-connection-string"
        objectType: "ssmparameter"
        objectAlias: "spring.datasource.url"
---
# Pod mounts secrets as files
env:
  - name: SPRING_CONFIG_IMPORT
    value: "optional:configtree:/mnt/secrets-store/"
volumeMounts:
  - name: secrets-store
    mountPath: "/mnt/secrets-store"
    readOnly: true
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: unicorn-store-secrets
```

Spring Boot's `configtree` reads files as properties: `/mnt/secrets-store/spring.datasource.url` → `spring.datasource.url`.

### ECR Create-on-Push

ECR repositories are created automatically when images are pushed (no explicit CDK definitions needed):
- Repository Creation Template applies to all repositories (ROOT prefix)
- Lifecycle policy: expires untagged after 1 day, keeps 10 recent tagged
- Tags: `Environment=workshop`, `ManagedBy=ecr-create-on-push`

### Lambda Functions

Lambda functions use inline Python code loaded from external files for CloudFormation compatibility:

| Function | Purpose |
|----------|---------|
| `workshop-ide-launcher` | EC2 instance launching with multi-AZ/instance-type failover |
| `workshop-ide-password` | Password retrieval Custom Resource |
| `workshop-ide-prefixlist` | CloudFront prefix list lookup |
| `workshop-codebuild-start` | CodeBuild project starter |
| `workshop-codebuild-report` | CodeBuild completion reporter |
| `workshop-database-setup` | Database schema initialization |
| `workshop-thread-dump-lambda` | Thread dump collection |

### Architecture Support

The IDE supports both ARM64 (Graviton) and x86_64 architectures:
- Architecture parameter in CDK determines instance types and binary downloads
- ARM64: m7g.xlarge, m6g.xlarge, c7g.xlarge, t4g.xlarge
- x86_64: m7i-flex.xlarge, m7a.xlarge, m6i.xlarge, m6a.xlarge, m5.xlarge, t3.xlarge

Scripts detect architecture and download appropriate binaries for kubectl, SAM CLI, eks-node-viewer, SOCI, yq, Helm.

### IDE Types

Two IDE options available via `IdeType` parameter:
- `CODE_EDITOR` (default): AWS Code Editor with token-based URL for Workshop Studio
- `VSCODE`: code-server with password authentication

### IDE Architecture

Architecture is controlled via `IdeArch` parameter:

| Architecture | Default | Instance Types |
|--------------|---------|----------------|
| `X86_64_AMD` | ✅ Yes | m6a.xlarge, m7a.xlarge |
| `X86_64_INTEL` | | m6i.xlarge, m5.xlarge, m7i.xlarge, m7i-flex.xlarge |
| `ARM64` | | m7g.xlarge, m6g.xlarge |

Scripts detect architecture and download appropriate binaries for kubectl, SAM CLI, eks-node-viewer, SOCI, yq, Helm.

### CloudFormation Signaling

Bulletproof signaling ensures deployments never hang:
- UserData traps errors and signals CloudFormation immediately
- Bootstrap script handles internal signaling for success/failure
- WaitCondition dependencies ensure outputs appear only after successful bootstrap
- Fast failure detection (<30 seconds) vs previous 30-minute timeout

### Script Organization

Shared functions in `functions.sh`:
- `retry_command(attempts, delay, fail_mode, tool_name, cmd)`: Configurable retry
- `retry_critical(tool_name, cmd)`: Exit on failure (5 attempts, 5s delay)
- `retry_optional(tool_name, cmd)`: Warning on failure (continues)
- `install_with_version(tool_name, install_cmd, version_cmd, fail_mode)`: Install and log version
- `log_info/success/error/warning(message)`: Emoji-based logging

Environment variables created in `/etc/profile.d/workshop.sh`:
- `AWS_REGION`, `AWS_DEFAULT_REGION`
- `ACCOUNT_ID`, `AWS_ACCOUNT_ID`
- `EC2_PRIVATE_IP`, `EC2_DOMAIN`, `EC2_URL`
- `IDE_DOMAIN`, `IDE_URL`, `IDE_PASSWORD`
- `JAVA_HOME`, `M2_HOME`

### Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| AWS CDK | 2.233.0 | Infrastructure as code |
| EKS v2 Alpha | 2.233.0-alpha.0 | EKS L2 construct |
| CDK Nag | 2.36.2 | Best practices validation |
| Java | 25 | CDK compilation |
| jqwik | 1.9.2 | Property-based testing |
