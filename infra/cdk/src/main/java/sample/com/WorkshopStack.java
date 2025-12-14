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
                aws iam create-service-linked-role --aws-service-name apprunner.amazonaws.com 2>/dev/null || true
                aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com 2>/dev/null || true
        """;

    public WorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

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
        Vpc vpc = new Vpc(this, "Vpc");

        // Create IDE props and get role for parallel resource creation
        IdeProps ideProps = IdeProps.builder()
            .vpc(vpc.getVpc())
            .gitBranch(gitBranch)
            .templateType(templateType)
            .build();
        Ide ide = new Ide(this, "Ide", ideProps);

        // CodeBuild for workshop setup
        CodeBuild codeBuild = new CodeBuild(this, "CodeBuild",
            CodeBuild.CodeBuildProps.builder()
                .projectName("workshop-setup")
                .vpc(vpc.getVpc())
                .environmentVariables(Map.of(
                    "TEMPLATE_TYPE", templateType,
                    "GIT_BRANCH", gitBranch))
                .buildSpec(buildSpec)
                .build());

        // Custom roles and database only for non-base templates
        if (!"base".equals(templateType)) {
            Roles roles = new Roles(this, "Roles");
            Database database = new Database(this, "Database", vpc.getVpc());

            // EKS cluster for java-on-aws and java-on-eks (exclude java-ai-agents)
            if (!"java-ai-agents".equals(templateType)) {
                Eks eks = new Eks(this, "Eks", Eks.EksProps.builder()
                    .vpc(vpc.getVpc())
                    .ideInstanceRole(ideProps.getIdeRole())
                    .ideInternalSecurityGroup(ide.getIdeInternalSecurityGroup())
                    .build());
            }
        }
    }
}