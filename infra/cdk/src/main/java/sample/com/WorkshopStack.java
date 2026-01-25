package sample.com;

import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.constructs.Construct;
import sample.com.constructs.*;
import sample.com.constructs.Ide.IdeProps;
import java.util.Map;

public class WorkshopStack extends Stack {

    private final String buildSpec = """
        version: 0.2
        env:
          shell: bash
        phases:
          install:
            commands:
              - |
                aws --version
                echo "Environment Variables:"
                echo "TEMPLATE_TYPE: $TEMPLATE_TYPE"
                echo "GIT_BRANCH: $GIT_BRANCH"
          build:
            commands:
              - |
                # Resolution for when creating the first service in the account
                aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com 2>/dev/null || true
                aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com 2>/dev/null || true
                aws iam create-service-linked-role --aws-service-name network.bedrock-agentcore.amazonaws.com 2>/dev/null || true
                aws iam create-service-linked-role --aws-service-name runtime-identity.bedrock-agentcore.amazonaws.com 2>/dev/null || true
        """;

    public WorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        // Resource naming prefix - change this to customize all resource names
        String prefix = "workshop";

        // Configuration values - get template type from CDK context (build time)
        String templateType = (String) this.getNode().tryGetContext("template.type");
        if (templateType == null) {
            templateType = "base"; // default
        }

        // Configuration values - get current git branch from CDK context
        String gitBranch = (String) this.getNode().tryGetContext("git.branch");
        if (gitBranch == null) {
            gitBranch = "main"; // fallback
        }

        // Template type flags
        boolean isImmersionDay = "java-on-aws-immersion-day".equals(templateType);
        boolean isEks = "java-on-amazon-eks".equals(templateType);
        boolean isSpringAi = "java-spring-ai-agents".equals(templateType);
        boolean isFullTemplate = isImmersionDay || isEks || isSpringAi;

        // Core infrastructure (always created)
        Vpc vpc = new Vpc(this, "Vpc", Vpc.VpcProps.builder()
            .prefix(prefix)
            .build());

        // Create IDE props and get role for parallel resource creation
        IdeProps ideProps = IdeProps.builder()
            .prefix(prefix)
            .vpc(vpc.getVpc())
            .gitBranch(gitBranch)
            .templateType(templateType)
            .build();
        Ide ide = new Ide(this, "Ide", ideProps);

        // CodeBuild for workshop setup (service-linked role creation)
        new CodeBuild(this, "CodeBuild",
            CodeBuild.CodeBuildProps.builder()
                .projectName(prefix + "-setup")
                .vpc(vpc.getVpc())
                .environmentVariables(Map.of(
                    "TEMPLATE_TYPE", templateType,
                    "GIT_BRANCH", gitBranch))
                .buildSpec(buildSpec)
                .build());

        // Shared workshop bucket
        WorkshopBucket workshopBucket = new WorkshopBucket(this, "WorkshopBucket",
            WorkshopBucket.WorkshopBucketProps.builder()
                .prefix(prefix)
                .build());

        // ECR Registry settings (Repository Creation Template for create-on-push)
        EcrRegistry ecrRegistry = new EcrRegistry(this, "EcrRegistry",
            EcrRegistry.EcrRegistryProps.builder()
                .prefix(prefix)
                .build());

        // Bedrock logging role (for model invocation logging to CloudWatch)
        software.amazon.awscdk.services.iam.Role.Builder.create(this, "BedrockLoggingRole")
            .roleName(prefix + "-bedrock-logging-role")
            .assumedBy(software.amazon.awscdk.services.iam.ServicePrincipal.Builder.create("bedrock.amazonaws.com")
                .conditions(java.util.Map.of(
                    "StringEquals", java.util.Map.of("aws:SourceAccount", this.getAccount()),
                    "ArnLike", java.util.Map.of("aws:SourceArn", "arn:aws:bedrock:" + this.getRegion() + ":" + this.getAccount() + ":*")
                ))
                .build())
            .description("Role for Bedrock model invocation logging to CloudWatch")
            .inlinePolicies(java.util.Map.of("BedrockLogging",
                software.amazon.awscdk.services.iam.PolicyDocument.Builder.create()
                    .statements(java.util.List.of(
                        software.amazon.awscdk.services.iam.PolicyStatement.Builder.create()
                            .effect(software.amazon.awscdk.services.iam.Effect.ALLOW)
                            .actions(java.util.List.of("logs:CreateLogStream", "logs:PutLogEvents"))
                            .resources(java.util.List.of("arn:aws:logs:" + this.getRegion() + ":" + this.getAccount() + ":log-group:/aws/bedrock/*"))
                            .build()
                    ))
                    .build()
            ))
            .build();

        // Full template resources (java-on-aws-immersion-day, java-on-amazon-eks, java-spring-ai-agents)
        if (isFullTemplate) {
            // Database
            Database database = new Database(this, "Database", Database.DatabaseProps.builder()
                .prefix(prefix)
                .vpc(vpc.getVpc())
                .build());

            // EKS cluster
            Eks eks = new Eks(this, "Eks", Eks.EksProps.builder()
                .prefix(prefix)
                .vpc(vpc.getVpc())
                .ideInstanceRole(ideProps.getIdeRole())
                .ideInternalSecurityGroup(ide.getIdeInternalSecurityGroup())
                .build());

            // Unicorn construct: EventBus, Roles, DB Setup (uses unicorn* naming for workshop content compatibility)
            Unicorn unicorn = new Unicorn(this, "Unicorn", Unicorn.UnicornProps.builder()
                .vpc(vpc.getVpc())
                .database(database)
                .workshopBucket(workshopBucket.getBucket())
                .build());

            // java-on-aws-immersion-day & java-on-amazon-eks specific resources
            if (isImmersionDay || isEks) {
                // ECR repository for unicorn-store-spring (manual ECS Express deployment)
                Repository.Builder.create(this, "UnicornStoreSpringEcr")
                    .repositoryName("unicorn-store-spring")
                    .imageScanOnPush(true)
                    .removalPolicy(RemovalPolicy.DESTROY)
                    .emptyOnDelete(true)
                    .build();

                // Thread Analysis (thread dump Lambda + API Gateway)
                new ThreadAnalysis(this, "ThreadAnalysis",
                    ThreadAnalysis.ThreadAnalysisProps.builder()
                        .prefix(prefix)
                        .vpc(vpc.getVpc())
                        .eksCluster(eks.getCluster())
                        .eksClusterName(eks.getClusterName())
                        .workshopBucket(workshopBucket.getBucket())
                        .build());

                // AI JVM Analyzer (Pod Identity role for ai-jvm-analyzer)
                new AiJvmAnalyzer(this, "AiJvmAnalyzer",
                    AiJvmAnalyzer.AiJvmAnalyzerProps.builder()
                        .workshopBucket(workshopBucket.getBucket())
                        .build());
            }

            // java-spring-ai-agents specific resources
            if (isSpringAi) {
                // AI Agent Runtime role for AgentCore deployment
                software.amazon.awscdk.services.iam.Role.Builder.create(this, "AiAgentRuntimeRole")
                    .roleName("aiagent-agentcore-runtime-role")
                    .assumedBy(software.amazon.awscdk.services.iam.ServicePrincipal.Builder.create("bedrock-agentcore.amazonaws.com")
                        .conditions(java.util.Map.of(
                            "StringEquals", java.util.Map.of("aws:SourceAccount", this.getAccount()),
                            "ArnLike", java.util.Map.of("aws:SourceArn", "arn:aws:bedrock-agentcore:" + this.getRegion() + ":" + this.getAccount() + ":*")
                        ))
                        .build())
                    .description("Role for AI Agent AgentCore Runtime")
                    .inlinePolicies(java.util.Map.of("AgentCoreExecutionPolicy",
                        software.amazon.awscdk.services.iam.PolicyDocument.Builder.create()
                            .statements(java.util.List.of(
                                software.amazon.awscdk.services.iam.PolicyStatement.Builder.create()
                                    .effect(software.amazon.awscdk.services.iam.Effect.ALLOW)
                                    .actions(java.util.List.of("bedrock:*", "bedrock-agentcore:*"))
                                    .resources(java.util.List.of("*"))
                                    .build(),
                                software.amazon.awscdk.services.iam.PolicyStatement.Builder.create()
                                    .effect(software.amazon.awscdk.services.iam.Effect.ALLOW)
                                    .actions(java.util.List.of("ecr:*", "logs:*", "xray:*", "cloudwatch:*"))
                                    .resources(java.util.List.of("*"))
                                    .build(),
                                software.amazon.awscdk.services.iam.PolicyStatement.Builder.create()
                                    .effect(software.amazon.awscdk.services.iam.Effect.ALLOW)
                                    .actions(java.util.List.of("aws-marketplace:Subscribe", "aws-marketplace:Unsubscribe", "aws-marketplace:ViewSubscriptions"))
                                    .resources(java.util.List.of("*"))
                                    .build()
                            ))
                            .build()
                    ))
                    .build();

                // AI Agent EKS Pod Identity role with Bedrock access
                software.amazon.awscdk.services.iam.Role aiAgentEksRole = software.amazon.awscdk.services.iam.Role.Builder.create(this, "AiAgentEksRole")
                    .roleName("aiagent-eks-pod-role")
                    .assumedBy(software.amazon.awscdk.services.iam.ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build())
                    .description("EKS Pod Identity role for AI Agent with Bedrock access")
                    .managedPolicies(java.util.List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockFullAccess")
                    ))
                    .build();
                // Add sts:TagSession for Pod Identity
                aiAgentEksRole.getAssumeRolePolicy().addStatements(
                    software.amazon.awscdk.services.iam.PolicyStatement.Builder.create()
                        .effect(software.amazon.awscdk.services.iam.Effect.ALLOW)
                        .principals(java.util.List.of(software.amazon.awscdk.services.iam.ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()))
                        .actions(java.util.List.of("sts:TagSession"))
                        .build()
                );
                // Grant DB secrets access (same as unicornstore-eks-pod-role)
                database.grantSecretsRead(aiAgentEksRole);

                // AI Agent Lambda execution role with Bedrock access
                software.amazon.awscdk.services.iam.Role aiAgentLambdaRole = software.amazon.awscdk.services.iam.Role.Builder.create(this, "AiAgentLambdaRole")
                    .roleName("aiagent-lambda-role")
                    .assumedBy(software.amazon.awscdk.services.iam.ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
                    .description("Lambda execution role for AI Agent with Bedrock access")
                    .managedPolicies(java.util.List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"),
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole"),
                        ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockFullAccess")
                    ))
                    .build();
                // Grant DB secrets access
                database.grantSecretsRead(aiAgentLambdaRole);

                // CodeBuild to push placeholder images (ECS Express needs images at deploy time)
                // ECR repos are created automatically via create-on-push (EcrRegistry)
                String placeholderBuildSpec = """
                    version: 0.2
                    env:
                      shell: bash
                    phases:
                      build:
                        commands:
                          - |
                            set -e
                            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                            ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

                            # ECR login with retry (network can be slow on first attempt)
                            for i in 1 2 3; do
                              echo "ECR login attempt $i..."
                              if aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY; then
                                echo "ECR login successful"
                                break
                              fi
                              if [ $i -eq 3 ]; then
                                echo "ECR login failed after 3 attempts"
                                exit 1
                              fi
                              sleep 10
                            done

                            # Create placeholder Dockerfile
                            cat > /tmp/Dockerfile << 'EOF'
                            FROM public.ecr.aws/docker/library/nginx:stable
                            RUN echo '<html><body><h1>Hello World!</h1><p>Build timestamp: '$(date)'</p></body></html>' > /usr/share/nginx/html/index.html
                            RUN sed -i 's/listen\\s*80;/listen 8080;/' /etc/nginx/conf.d/default.conf
                            EXPOSE 8080
                            CMD ["nginx", "-g", "daemon off;"]
                            EOF

                            # Build and push placeholder image (create-on-push creates repo)
                            docker build -t placeholder /tmp
                            docker tag placeholder $ECR_REGISTRY/aiagent:latest
                            docker push $ECR_REGISTRY/aiagent:latest
                    """;

                CodeBuild placeholderImageBuild = new CodeBuild(this, "PlaceholderImageBuild",
                    CodeBuild.CodeBuildProps.builder()
                        .projectName(prefix + "-placeholder-images")
                        .vpc(vpc.getVpc())
                        .privilegedMode(true)
                        .environmentVariables(Map.of(
                            "TEMPLATE_TYPE", templateType))
                        .buildSpec(placeholderBuildSpec)
                        .dependencies(java.util.List.of(
                            vpc.getConcreteVpc(),  // Ensures NAT Gateway is ready
                            ecrRegistry.getRepositoryCreationTemplate()  // Ensures ECR create-on-push is configured
                        ))
                        .build());

                // ECS Express Service for AI Agent
                new EcsExpressService(this, "AiAgent",
                    EcsExpressService.EcsExpressServiceProps.builder()
                        .appName("aiagent")
                        .vpc(vpc.getVpc())
                        .database(database)
                        .configureTaskRole(role ->
                            role.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockFullAccess")))
                        .dependsOn(placeholderImageBuild.getCustomResource())
                        .build());
            }

            // Pre-delete cleanup (removes VPC endpoints, CloudWatch logs, S3 contents before stack deletion)
            new CfnPreDeleteCleanup(this, "CfnPreDeleteCleanup",
                CfnPreDeleteCleanup.CfnPreDeleteCleanupProps.builder()
                    .prefix(prefix)
                    .vpc(vpc.getVpc())
                    .build());
        }
    }
}