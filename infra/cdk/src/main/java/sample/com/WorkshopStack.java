package sample.com;

import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.ecr.Repository;
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

        // Full template resources (java-on-aws-immersion-day, java-on-amazon-eks, java-spring-ai-agents)
        if (isFullTemplate) {
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

            // Shared workshop bucket
            WorkshopBucket workshopBucket = new WorkshopBucket(this, "WorkshopBucket",
                WorkshopBucket.WorkshopBucketProps.builder()
                    .prefix(prefix)
                    .build());

            // ECR Registry settings (Repository Creation Template for create-on-push)
            new EcrRegistry(this, "EcrRegistry",
                EcrRegistry.EcrRegistryProps.builder()
                    .prefix(prefix)
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
                            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                            aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

                            # Create placeholder Dockerfile
                            cat > /tmp/Dockerfile << 'EOF'
                            FROM public.ecr.aws/docker/library/nginx:stable
                            RUN echo '<html><body><h1>Hello World!</h1><p>Build timestamp: '$(date)'</p></body></html>' > /usr/share/nginx/html/index.html
                            RUN sed -i 's/listen\\s*80;/listen 8080;/' /etc/nginx/conf.d/default.conf
                            EXPOSE 8080
                            CMD ["nginx", "-g", "daemon off;"]
                            EOF

                            # Build and push placeholder to both repos (create-on-push creates repos)
                            docker build -t placeholder /tmp
                            docker tag placeholder $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/unicorn-spring-ai-agent:latest
                            docker tag placeholder $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/unicorn-store-spring:latest
                            docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/unicorn-spring-ai-agent:latest
                            docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/unicorn-store-spring:latest
                    """;

                CodeBuild placeholderImageBuild = new CodeBuild(this, "PlaceholderImageBuild",
                    CodeBuild.CodeBuildProps.builder()
                        .projectName(prefix + "-placeholder-images")
                        .vpc(vpc.getVpc())
                        .privilegedMode(true)
                        .environmentVariables(Map.of(
                            "TEMPLATE_TYPE", templateType))
                        .buildSpec(placeholderBuildSpec)
                        .build());

                // ECS Express Service for Spring AI Agent
                new EcsExpressService(this, "SpringAiAgent",
                    EcsExpressService.EcsExpressServiceProps.builder()
                        .appName("unicorn-spring-ai-agent")
                        .vpc(vpc.getVpc())
                        .database(database)
                        .unicorn(unicorn)
                        .dependsOn(placeholderImageBuild.getCustomResource())
                        .build());

                // ECS Express Service for MCP Server
                new EcsExpressService(this, "McpServer",
                    EcsExpressService.EcsExpressServiceProps.builder()
                        .appName("unicorn-store-spring")
                        .vpc(vpc.getVpc())
                        .database(database)
                        .unicorn(unicorn)
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