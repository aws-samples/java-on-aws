package sample.com;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
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

        // java-on-aws-immersion-day and java-on-amazon-eks specific resources (CodeBuild for service-linked roles)
        if ("java-on-aws-immersion-day".equals(templateType) || "java-on-amazon-eks".equals(templateType)) {
            // CodeBuild for workshop setup (service-linked role creation)
            new CodeBuild(this, "CodeBuild",
                CodeBuild.CodeBuildProps.builder()
                    .prefix(prefix)
                    .projectName(prefix + "-setup")
                    .vpc(vpc.getVpc())
                    .environmentVariables(Map.of(
                        "TEMPLATE_TYPE", templateType,
                        "GIT_BRANCH", gitBranch))
                    .buildSpec(buildSpec)
                    .build());

            // Database, EKS, PerformanceAnalysis, Unicorn
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

            // Shared workshop bucket for thread dumps and profiling data
            WorkshopBucket workshopBucket = new WorkshopBucket(this, "WorkshopBucket",
                WorkshopBucket.WorkshopBucketProps.builder()
                    .prefix(prefix)
                    .build());

            // ECR Registry settings (Repository Creation Template for create-on-push)
            EcrRegistry ecrRegistry = new EcrRegistry(this, "EcrRegistry",
                EcrRegistry.EcrRegistryProps.builder()
                    .prefix(prefix)
                    .build());

            // Thread Analysis (thread dump Lambda + API Gateway)
            ThreadAnalysis threadAnalysis = new ThreadAnalysis(this, "ThreadAnalysis",
                ThreadAnalysis.ThreadAnalysisProps.builder()
                    .prefix(prefix)
                    .vpc(vpc.getVpc())
                    .eksCluster(eks.getCluster())
                    .eksClusterName(eks.getClusterName())
                    .workshopBucket(workshopBucket.getBucket())
                    .build());

            // JVM Analysis (Pod Identity role for jvm-analysis-service)
            JvmAnalysis jvmAnalysis = new JvmAnalysis(this, "JvmAnalysis",
                JvmAnalysis.JvmAnalysisProps.builder()
                    .workshopBucket(workshopBucket.getBucket())
                    .build());

            // Unicorn construct: Roles + DB Setup (uses unicorn* naming for workshop content compatibility)
            Unicorn unicorn = new Unicorn(this, "Unicorn", Unicorn.UnicornProps.builder()
                .vpc(vpc.getVpc())
                .eksRolesEnabled(true)
                .ecsRolesEnabled(false)
                .database(database)
                .workshopBucket(workshopBucket.getBucket())
                .build());
        }
    }
}