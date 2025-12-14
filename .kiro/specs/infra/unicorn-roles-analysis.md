# Unicorn Roles Analysis & Implementation Plan

## 🎯 **Requirement Reference**
- **Task 10.2**: "Include Bedrock permissions for AI workshops in the unified roles"
- **Requirement 6.3**: "System SHALL retrieve passwords securely from AWS Secrets Manager using IAM roles"
- **Design**: Roles construct SHALL consolidate all IAM roles and policies

## 🔐 **Unicorn Role Groups (From Original Infrastructure)**

### **🏗️ Core Infrastructure Roles**
| **Role Name** | **Purpose** | **Managed Policies** | **Workshop Types** |
|---------------|-------------|---------------------|-------------------|
| `unicornstore-ide-user` | EC2 instance profile | ReadOnly, SSM, CloudWatch, AdministratorAccess | All |
| `unicornstore-codebuild-user` | CodeBuild execution | AdministratorAccess | All |

### **☸️ EKS Cluster Roles**
| **Role Name** | **Purpose** | **Managed Policies** | **Workshop Types** |
|---------------|-------------|---------------------|-------------------|
| `unicorn-store-eks-cluster-role` | EKS cluster service | AmazonEKSClusterPolicy, AmazonEKSNetworkingPolicy | java-on-eks |
| `unicorn-store-eks-cluster-node-role` | EKS node group | AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly | java-on-eks |

### **🚀 Application Workload Roles**
| **Role Name** | **Purpose** | **Managed Policies** | **Workshop Types** |
|---------------|-------------|---------------------|-------------------|
| `unicornstore-eks-pod-role` | Application pods | CloudWatchAgentServerPolicy, AmazonBedrockLimitedAccess | java-on-eks |
| `unicornstore-lambda-bedrock-role` | Lambda Bedrock access | AmazonBedrockLimitedAccess, AWSLambdaVPCAccessExecutionRole | java-ai-agents, java-spring-ai-agents |
| `jvm-analysis-service-eks-pod-role` | JVM analysis service | AmazonBedrockLimitedAccess | java-on-eks |

### **🐳 Container Platform Roles**
| **Role Name** | **Purpose** | **Managed Policies** | **Workshop Types** |
|---------------|-------------|---------------------|-------------------|
| `unicornstore-ecs-task-role` | ECS task execution | CloudWatchLogsFullAccess, AmazonSSMReadOnlyAccess | java-on-eks |
| `unicornstore-ecs-task-execution-role` | ECS task definition | CloudWatchLogsFullAccess, AmazonSSMReadOnlyAccess | java-on-eks |
| `unicornstore-apprunner-role` | App Runner service | Custom policies | java-on-eks |
| `unicornstore-apprunner-ecr-access-role` | ECR access for App Runner | AWSAppRunnerServicePolicyForECRAccess | java-on-eks |

### **🔐 Secrets & Security Roles**
| **Role Name** | **Purpose** | **Managed Policies** | **Workshop Types** |
|---------------|-------------|---------------------|-------------------|
| `unicornstore-eks-eso-role` | External Secrets Operator | Custom (pods.eks.amazonaws.com) | java-on-eks |
| `unicornstore-eks-eso-sm-role` | ESO Secrets Manager access | Custom SecretsManager policy | java-on-eks |

## 📋 **Implementation Strategy**

### **Phase 1: Base Template (✅ Complete)**
- ✅ `ide-user` (equivalent to `unicornstore-ide-user`)
- ✅ CodeBuild roles
- ✅ Lambda execution roles

### **Phase 2: Database Construct (Future)**
```java
// Database-specific roles
private Role databaseSetupLambdaRole;
```

### **Phase 3: EKS Construct (Future)**
```java
// EKS cluster roles
private Role eksClusterRole;        // unicorn-store-eks-cluster-role
private Role eksNodeRole;           // unicorn-store-eks-cluster-node-role

// Application workload roles
private Role eksPodRole;            // unicornstore-eks-pod-role
private Role eksEsoRole;            // unicornstore-eks-eso-role
private Role eksEsoSmRole;          // unicornstore-eks-eso-sm-role
```

### **Phase 4: Container Construct (Future)**
```java
// Container platform roles
private Role ecsTaskRole;           // unicornstore-ecs-task-role
private Role ecsTaskExecutionRole;  // unicornstore-ecs-task-execution-role
private Role appRunnerRole;         // unicornstore-apprunner-role
private Role appRunnerEcrRole;      // unicornstore-apprunner-ecr-access-role
```

### **Phase 5: AI/Bedrock Construct (Future)**
```java
// AI/ML workload roles
private Role lambdaBedrockRole;     // unicornstore-lambda-bedrock-role
private Role jvmAnalysisRole;       // jvm-analysis-service-eks-pod-role
```

## 🎯 **Roles Construct Design**

### **Conditional Role Creation**
```java
public class Roles extends Construct {
    // Always created (base template)
    private final Role ideUserRole;
    private final Role codeBuildRole;

    // Conditionally created based on workshop type
    private Role eksClusterRole;
    private Role eksPodRole;
    private Role lambdaBedrockRole;

    public Roles(Construct scope, String id, RolesProps props) {
        // Base roles (always)
        this.ideUserRole = createIdeUserRole();
        this.codeBuildRole = createCodeBuildRole();

        // Workshop-specific roles
        if (props.includeEks()) {
            this.eksClusterRole = createEksClusterRole();
            this.eksPodRole = createEksPodRole();
        }

        if (props.includeBedrock()) {
            this.lambdaBedrockRole = createLambdaBedrockRole();
        }
    }
}
```

### **Role Naming Convention**
- **Base roles**: `ide-user`, `setup-codebuild-user`
- **Workshop roles**: `unicornstore-{service}-{purpose}-role`
- **Service-specific**: `jvm-analysis-service-{purpose}-role`

## ✅ **Next Steps**
1. **Document current base roles** (✅ Complete)
2. **Design Roles construct** with conditional creation
3. **Implement EKS roles** for java-on-eks template
4. **Implement Bedrock roles** for AI workshops
5. **Test role permissions** across workshop types