# Infrastructure Migration Gap Analysis

## Overview

Comprehensive comparison between original infrastructure (`infrastructure/`) and new unified infrastructure (`infra/`). Sources analyzed: CDK constructs, core modules, and setup scripts.

---

## CDK Source Structure

### Original (`infrastructure/cdk/`)

```
com/unicorn/
├── Stacks (5)
│   ├── UnicornStoreStack.java      # java-on-aws
│   ├── JavaOnEksStack.java         # java-on-eks
│   ├── JavaAiAgentsStack.java      # java-ai-agents
│   ├── SpringAIStack.java          # spring-ai
│   └── IdeStack.java               # base
├── constructs/ (6)
│   ├── VSCodeIde.java, WorkshopVpc.java, CodeBuildResource.java
│   ├── EksCluster.java, EcsCluster.java, WorkshopFunction.java
└── core/ (7)
    ├── InfrastructureCore.java     # DB, EventBridge, S3, Bedrock role
    ├── InfrastructureContainers.java # ECR, App Runner, ECS roles
    ├── InfrastructureEks.java      # EKS Pod roles, ESO roles
    ├── InfrastructureJvmAnalysis.java # JVM ECR + roles
    ├── InfrastructureMonitoringJVM.java # Thread dump Lambda + API GW
    ├── DatabaseSetup.java          # DB schema Lambda
    └── UnicornStoreSpringLambda.java
```

### New (`infra/cdk/`)

```
sample/com/
├── WorkshopStack.java              # Unified (TEMPLATE_TYPE conditional)
├── WorkshopApp.java
└── constructs/ (7)
    ├── Vpc.java          ✅
    ├── Ide.java          ✅
    ├── CodeBuild.java    ✅
    ├── Database.java     ✅
    ├── Eks.java          ✅ (v2 alpha, Auto Mode)
    ├── Lambda.java       ✅
    └── Roles.java        ⚠️ EMPTY
```

---

## Constructs Implementation Status

| Original | New | Status | Notes |
|----------|-----|--------|-------|
| WorkshopVpc | Vpc | ✅ | Equivalent |
| VSCodeIde | Ide | ✅ | UserData-based bootstrap |
| CodeBuildResource | CodeBuild | ✅ | Equivalent |
| EksCluster | Eks | ✅ | v2 alpha, Auto Mode, native add-ons |
| DatabaseSetup | Database | ✅ | Consolidated RDS + Lambda |
| WorkshopFunction | Lambda | ✅ | Reusable construct |
| InfrastructureCore | - | ⚠️ Partial | S3, EventBridge missing |
| InfrastructureContainers | - | ❌ | ECR, App Runner, ECS roles |
| InfrastructureEks | - | ❌ | EKS Pod roles, ESO roles |
| EcsCluster | - | ❌ | ECS Fargate + ALB |
| InfrastructureJvmAnalysis | - | ❌ | JVM analysis |
| InfrastructureMonitoringJVM | - | ❌ | Thread dump API |

---

## Services by Workshop Matrix

| Service | base | java-on-aws | java-on-eks | java-ai-agents | spring-ai |
|---------|------|-------------|-------------|----------------|-----------|
| Vpc | ✅ | ✅ | ✅ | ✅ | ✅ |
| Ide | ✅ | ✅ | ✅ | ✅ | ✅ |
| CodeBuild | ✅ | ✅ | ✅ | ✅ | ✅ |
| Database | ❌ | ✅ | ✅ | ✅ | ✅ |
| EKS | ❌ | ✅ | ✅ | ❌ | ✅ |
| ECR | ❌ | ✅ (1) | ✅ (2) | ✅ (1) | ✅ (2) |
| ECS/Fargate | ❌ | ❌ | ❌ | ✅ (1) | ✅ (2) |
| ALB | ❌ | ❌ | ❌ | ✅ (1) | ✅ (2) |
| App Runner | ❌ | ✅ | ✅ | ❌ | ❌ |
| S3 Bucket | ❌ | ✅ | ✅ | ✅ | ✅ |
| EventBridge | ❌ | ✅ | ✅ | ✅ | ✅ |
| API Gateway | ❌ | ✅ | ❌ | ❌ | ❌ |

---

## IAM Roles Analysis

### Common Roles (All Non-Base Workshops)

| Role | Service Principal | Policies | Source |
|------|------------------|----------|--------|
| `unicornstore-lambda-bedrock-role` | lambda | BedrockLimitedAccess, LambdaVPCAccess | InfrastructureCore |

### EKS Roles (java-on-aws, java-on-eks, spring-ai)

| Role | Service Principal | Policies | Source |
|------|------------------|----------|--------|
| `unicornstore-eks-pod-role` | pods.eks | CloudWatchAgent, BedrockLimitedAccess | InfrastructureEks |
| `unicornstore-eks-eso-role` | pods.eks | (trust only) | InfrastructureEks |
| `unicornstore-eks-eso-sm-role` | eks-eso-role | db-secret-policy | InfrastructureEks |

### Container Roles (java-on-aws, java-on-eks)

| Role | Service Principal | Policies | Source |
|------|------------------|----------|--------|
| `unicornstore-apprunner-role` | tasks.apprunner | xray, secrets, ssm | InfrastructureContainers |
| `unicornstore-apprunner-ecr-access-role` | build.apprunner | AppRunnerECRAccess | InfrastructureContainers |
| `unicornstore-ecs-task-role` | ecs-tasks | CloudWatchLogs, SSMReadOnly | InfrastructureContainers |
| `unicornstore-ecs-task-execution-role` | ecs-tasks | ECSTaskExecution | InfrastructureContainers |

### ECS Cluster Roles (java-ai-agents, spring-ai)

| Role | Service Principal | Policies | Source |
|------|------------------|----------|--------|
| `{app}-ecs-task-role` | ecs-tasks | BedrockFullAccess | EcsCluster (dynamic) |
| `{app}-ecs-task-execution-role` | ecs-tasks | ECSTaskExecution | EcsCluster (dynamic) |

### JVM Analysis Roles (java-on-aws, java-on-eks)

| Role | Service Principal | Policies | Source |
|------|------------------|----------|--------|
| `jvm-analysis-service-eks-pod-role` | pods.eks | BedrockLimitedAccess | InfrastructureJvmAnalysis |
| `lambda-eks-access-role` | lambda | LambdaBasic, LambdaVPCAccess | InfrastructureMonitoringJVM |

---

## Script-Created AWS Resources

### Original Setup Scripts (`infrastructure/scripts/setup/`)

| Script | AWS Resources Created | Workshop |
|--------|----------------------|----------|
| `eks.sh` | Pod Identity Associations, EKS Access Entry | All EKS |
| `monitoring.sh` | ConfigMap (Grafana datasource) | java-on-aws |
| `jmx-bedrock-setup.sh` | ECR, ECS Cluster, ALB, Target Group, Security Groups, ECS Service | java-on-aws |
| `java-on-eks/4-jvm-analysis-service.sh` | Pod Identity Association | java-on-eks |

### Original Deploy Scripts (`infrastructure/scripts/deploy/`)

| Script | AWS Resources Created | Workshop |
|--------|----------------------|----------|
| `ecs.sh` | ECS Cluster, Security Groups, ALB, Target Group, Listener, ECS Service | Manual deploy |
| `apprunner.sh` | App Runner Service | Manual deploy |
| `eks.sh` | K8s Deployment, Service, Ingress | Manual deploy |

### New Setup Scripts (`infra/scripts/setup/`)

| Script | AWS Resources Created | Status |
|--------|----------------------|--------|
| `eks.sh` | K8s StorageClass, IngressClass, SecretProviderClass | ✅ Complete |

### Script Gap Analysis

| Original Script | New Script | Status |
|-----------------|------------|--------|
| `eks.sh` (Pod Identity, ESO, Namespaces) | `eks.sh` (StorageClass, IngressClass) | ⚠️ Missing: Pod Identity, ESO, Namespaces |
| `monitoring.sh` | - | ❌ Missing |
| `jmx-bedrock-setup.sh` | - | ❌ Missing |
| `java-on-eks/*.sh` | - | ❌ Missing |

---

## Missing Constructs Detail

### Priority 1: HIGH

| Construct | Components |
|-----------|------------|
| **Roles.java** | Lambda Bedrock, EKS Pod, ESO, App Runner, ECS roles |
| **Ecr.java** | ECR repositories with workshop-* naming |
| **S3 + EventBridge** | Workshop bucket, event bus |

### Priority 2: HIGH (AI Workshops)

| Construct | Components |
|-----------|------------|
| **Ecs.java** | ECS Cluster, Fargate Service, ALB, Task Roles |

### Priority 3: MEDIUM

| Construct | Components |
|-----------|------------|
| **AppRunner.java** | VPC Connector, Roles |
| **eks.sh updates** | Pod Identity, ESO, Namespaces |

### Priority 4: LOW

| Construct | Components |
|-----------|------------|
| **JvmAnalysis.java** | ECR, Pod role |
| **ApiGateway.java** | Private API, VPC Endpoint |
| **monitoring.sh** | Grafana setup |

---

## WorkshopStack Conditional Logic

### Current

```java
if (!"base".equals(templateType)) {
    Roles roles = new Roles(this, "Roles");  // ⚠️ EMPTY
    Database database = new Database(this, "Database", vpc);

    if (!"java-ai-agents".equals(templateType)) {
        Eks eks = new Eks(this, "Eks", ...);
    }
}
```

### Required Updates

```java
if (!"base".equals(templateType)) {
    Roles roles = new Roles(this, "Roles", RolesProps.builder()
        .includeEks(!"java-ai-agents".equals(templateType))
        .includeContainers(true)
        .build());
    Database database = new Database(this, "Database", vpc);
    Ecr ecr = new Ecr(this, "Ecr");
    S3 s3 = new S3(this, "S3");

    if (!"java-ai-agents".equals(templateType)) {
        Eks eks = new Eks(this, "Eks", ...);
    }

    // ECS for AI workshops
    if ("java-ai-agents".equals(templateType) || "spring-ai".equals(templateType)) {
        new Ecs(this, "McpServer", "unicorn-store-spring", ...);
    }
    if ("spring-ai".equals(templateType)) {
        new Ecs(this, "AiAgent", "unicorn-spring-ai-agent", ...);
    }

    // App Runner for container workshops
    if ("java-on-aws".equals(templateType) || "java-on-eks".equals(templateType)) {
        new AppRunner(this, "AppRunner", ...);
    }
}
```

---

## Naming Convention Migration

| Original | New |
|----------|-----|
| `unicorn-store-spring` | `workshop-app` |
| `jvm-analysis-service` | `workshop-jvm-analysis` |
| `unicorn-spring-ai-agent` | `workshop-ai-agent` |
| `unicornstore-*-role` | `workshop-*-role` |
| `unicornstore-vpc-connector` | `workshop-vpc-connector` |
| `unicorns` (EventBridge) | `workshop` |

---

## Summary

| Category | Original | New | Gap |
|----------|----------|-----|-----|
| Stacks | 5 | 1 (unified) | ✅ Better |
| Constructs | 6 | 7 | ✅ Complete |
| Core Modules | 7 | 1 | ❌ 6 missing |
| IAM Roles | ~14 | 2 | ❌ ~12 missing |
| ECR Repos | 3 | 0 | ❌ 3 missing |
| ECS Clusters | 3 | 0 | ❌ 3 missing |
| Setup Scripts | 10+ | 2 | ❌ 8+ missing |

---

*Generated: December 2025*
