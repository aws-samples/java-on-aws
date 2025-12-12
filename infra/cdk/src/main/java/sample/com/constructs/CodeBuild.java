package sample.com.constructs;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.codebuild.*;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.constructs.Construct;
import java.util.Map;

public class CodeBuild extends Construct {
    private final Project setupProject;

    public CodeBuild(final Construct scope, final String id, final IVpc vpc, final Roles roles, final Map<String, String> environmentVariables) {
        super(scope, id);

        // Create CodeBuild project for workshop setup
        this.setupProject = Project.Builder.create(this, "WorkshopSetup")
            .projectName("workshop-setup")
            .description("Automated workshop environment setup")
            .role(roles.getCodeBuildRole())
            .vpc(vpc)
            .subnetSelection(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .source(Source.gitHub(GitHubSourceProps.builder()
                .owner("aws-samples")
                .repo("java-on-aws")
                .build()))
            .environment(BuildEnvironment.builder()
                .buildImage(LinuxBuildImage.STANDARD_7_0)
                .computeType(ComputeType.SMALL)
                .environmentVariables(environmentVariables.entrySet().stream()
                    .collect(java.util.stream.Collectors.toMap(
                        Map.Entry::getKey,
                        entry -> BuildEnvironmentVariable.builder()
                            .value(entry.getValue())
                            .build()
                    )))
                .build())
            .buildSpec(BuildSpec.fromObject(Map.of(
                "version", "0.2",
                "phases", Map.of(
                    "install", Map.of(
                        "on-failure", "ABORT",
                        "commands", java.util.List.of(
                            "echo '📦 Installing dependencies...'",
                            "yum update -y && yum install -y git kubectl helm jq || exit 1"
                        )
                    ),
                    "pre_build", Map.of(
                        "on-failure", "ABORT",
                        "commands", java.util.List.of(
                            "echo '🔄 Preparing workshop setup...'",
                            "git clone https://github.com/aws-samples/java-on-aws || exit 1",
                            "cd java-on-aws/infra/scripts",
                            "chmod +x workshops/*.sh setup/*.sh lib/*.sh"
                        )
                    ),
                    "build", Map.of(
                        "on-failure", "ABORT",
                        "commands", java.util.List.of(
                            "echo '⏳ Waiting for infrastructure (timeout: 30 minutes)...'",
                            "timeout 1800 ./lib/wait-for-resources.sh \"$STACK_NAME\" || {",
                            "  echo '⏰ TIMEOUT: Infrastructure not ready within 30 minutes';",
                            "  echo '🔍 Check CloudFormation stack events for details';",
                            "  exit 1;",
                            "}",
                            "echo '🔧 Running workshop-specific setup...'",
                            "cd workshops && ./${STACK_NAME}.sh || {",
                            "  echo '❌ Workshop setup failed for $STACK_NAME';",
                            "  echo '🔍 Check setup logs above for specific error';",
                            "  exit 1;",
                            "}"
                        )
                    ),
                    "post_build", Map.of(
                        "commands", java.util.List.of(
                            "if [ $CODEBUILD_BUILD_SUCCEEDING -eq 1 ]; then",
                            "  echo '✅ Workshop setup completed successfully!';",
                            "else",
                            "  echo '❌ Workshop setup failed - check logs above';",
                            "  echo '📞 Contact workshop support with build ID: $CODEBUILD_BUILD_ID';",
                            "fi"
                        )
                    )
                )
            )))
            .timeout(Duration.minutes(60))
            .build();
    }

    public Project getSetupProject() {
        return setupProject;
    }
}