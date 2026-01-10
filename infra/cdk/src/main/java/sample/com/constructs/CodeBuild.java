package sample.com.constructs;

import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.codebuild.*;
import software.amazon.awscdk.services.events.*;
import software.amazon.awscdk.services.events.targets.LambdaFunction;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.constructs.Construct;

import java.util.Map;
import java.util.List;
import java.util.Arrays;
import org.yaml.snakeyaml.Yaml;

public class CodeBuild extends Construct {
    private final CustomResource customResource;
    private final Project codebuildProject;
    private final Role codeBuildRole;
    private final Role lambdaRole;

    public static class CodeBuildProps {
        private String projectName = "workshop-setup";
        private IBuildImage buildImage = LinuxBuildImage.AMAZON_LINUX_2_5;
        private ComputeType computeType = ComputeType.MEDIUM;
        private Duration timeout = Duration.minutes(30);
        private Boolean privilegedMode = false;
        private IVpc vpc;
        private Map<String, String> environmentVariables;
        private String buildSpec;

        public static CodeBuildProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private CodeBuildProps props = new CodeBuildProps();

            public Builder projectName(String projectName) { props.projectName = projectName; return this; }
            public Builder buildImage(IBuildImage buildImage) { props.buildImage = buildImage; return this; }
            public Builder computeType(ComputeType computeType) { props.computeType = computeType; return this; }
            public Builder timeout(Duration timeout) { props.timeout = timeout; return this; }
            public Builder privilegedMode(Boolean privilegedMode) { props.privilegedMode = privilegedMode; return this; }
            public Builder vpc(IVpc vpc) { props.vpc = vpc; return this; }
            public Builder environmentVariables(Map<String, String> environmentVariables) { props.environmentVariables = environmentVariables; return this; }
            public Builder buildSpec(String buildSpec) { props.buildSpec = buildSpec; return this; }

            public CodeBuildProps build() { return props; }
        }

        // Getters
        public String getProjectName() { return projectName; }
        public IBuildImage getBuildImage() { return buildImage; }
        public ComputeType getComputeType() { return computeType; }
        public Duration getTimeout() { return timeout; }
        public Boolean getPrivilegedMode() { return privilegedMode; }
        public IVpc getVpc() { return vpc; }
        public Map<String, String> getEnvironmentVariables() { return environmentVariables; }
        public String getBuildSpec() { return buildSpec; }
    }

    public CodeBuild(final Construct scope, final String id, final IVpc vpc, final Map<String, String> environmentVariables, final String buildSpec) {
        this(scope, id, CodeBuildProps.builder()
            .vpc(vpc)
            .environmentVariables(environmentVariables)
            .buildSpec(buildSpec)
            .build());
    }

    public CodeBuild(final Construct scope, final String id, final CodeBuildProps props) {
        super(scope, id);

        // Create CodeBuild service role
        this.codeBuildRole = Role.Builder.create(this, "Role")
            .assumedBy(ServicePrincipal.Builder.create("codebuild.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("PowerUserAccess")
            ))
            .build();

        // Create Lambda role for CodeBuild Lambda functions
        this.lambdaRole = Role.Builder.create(this, "LambdaRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
            ))
            .build();

        // Add CodeBuild permissions for Lambda functions
        PolicyStatement codeBuildPermissions = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "codebuild:StartBuild",
                "codebuild:BatchGetBuilds"
            ))
            .resources(List.of("*"))
            .build();

        lambdaRole.addToPolicy(codeBuildPermissions);

        // Convert environment variables to CodeBuild format
        Map<String, BuildEnvironmentVariable> codeBuildEnvVars = props.getEnvironmentVariables().entrySet().stream()
            .collect(java.util.stream.Collectors.toMap(
                Map.Entry::getKey,
                entry -> BuildEnvironmentVariable.builder()
                    .value(entry.getValue())
                    .type(BuildEnvironmentVariableType.PLAINTEXT)
                    .build()
            ));

        // Create CodeBuild project
        this.codebuildProject = Project.Builder.create(this, "Project")
            .role(codeBuildRole)
            .vpc(props.getVpc())
            .projectName(props.getProjectName())
            .subnetSelection(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .environment(BuildEnvironment.builder()
                .buildImage(props.getBuildImage())
                .computeType(props.getComputeType())
                .privileged(props.getPrivilegedMode())
                .build())
            .buildSpec(BuildSpec.fromObjectToYaml(new Yaml().load(props.getBuildSpec())))
            .environmentVariables(codeBuildEnvVars)
            .timeout(props.getTimeout())
            .build();

        // Create start build Lambda function
        var startLambda = new Lambda(this, "StartLambda",
            "/lambda/codebuild-start.py", props.getProjectName() + "-start", Duration.minutes(2), lambdaRole);
        Function startBuildFunction = startLambda.getFunction();

        // Create report build Lambda function
        var reportLambda = new Lambda(this, "ReportLambda",
            "/lambda/codebuild-report.py", props.getProjectName() + "-report", Duration.minutes(2), lambdaRole);
        Function reportBuildFunction = reportLambda.getFunction();

        // Create EventBridge rule for build completion
        Rule buildCompleteRule = Rule.Builder.create(this, "CompleteRule")
            .description(props.getProjectName() + " build complete")
            .eventPattern(EventPattern.builder()
                .source(Arrays.asList("aws.codebuild"))
                .detailType(Arrays.asList("CodeBuild Build State Change"))
                .detail(Map.of(
                    "build-status", Arrays.asList("SUCCEEDED", "FAILED", "STOPPED"),
                    "project-name", Arrays.asList(this.codebuildProject.getProjectName())
                ))
                .build())
            .targets(Arrays.asList(new LambdaFunction(reportBuildFunction)))
            .build();

        // Create custom resource to trigger the build
        this.customResource = CustomResource.Builder.create(this, "Resource")
            .serviceToken(startBuildFunction.getFunctionArn())
            .properties(Map.of(
                "ProjectName", this.codebuildProject.getProjectName(),
                "CodeBuildIamRoleArn", this.codebuildProject.getRole().getRoleArn(),
                "ContentHash", String.valueOf(System.currentTimeMillis())
            ))
            .build();

        this.customResource.getNode().addDependency(buildCompleteRule);
        this.customResource.getNode().addDependency(reportBuildFunction);
    }

    public Project getCodeBuildProject() {
        return this.codebuildProject;
    }

    public CustomResource getCustomResource() {
        return this.customResource;
    }
}