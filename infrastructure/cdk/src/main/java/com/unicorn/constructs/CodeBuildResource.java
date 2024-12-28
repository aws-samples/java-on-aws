package com.unicorn.constructs;

import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.CustomResourceProps;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.codebuild.*;
import software.amazon.awscdk.services.events.*;
import software.amazon.awscdk.services.events.targets.LambdaFunction;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;

import software.constructs.Construct;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Map;
import java.util.List;
import java.util.ArrayList;
import java.util.Arrays;

public class CodeBuildResource extends Construct {
    private final CustomResource customResource;
    private final Project codebuildProject;

    public static class CodeBuildCustomResourceProps {
        private IBuildImage buildImage = LinuxBuildImage.AMAZON_LINUX_2_5;
        private ComputeType computeType = ComputeType.SMALL;
        private String buildspec;
        private Map<String, BuildEnvironmentVariable> environmentVariables;
        private Duration codeBuildTimeout = Duration.minutes(15);
        private Boolean privilegedMode = false;
        private List<IManagedPolicy> additionalIamPolicies = new ArrayList<>();
        private IRole role;
        private IVpc vpc;

        public IBuildImage getBuildImage() {
            return buildImage;
        }
        public void setBuildImage(IBuildImage buildImage) {
            this.buildImage = buildImage;
        }
        public ComputeType getComputeType() {
            return computeType;
        }
        public void setComputeType(ComputeType computeType) {
            this.computeType = computeType;
        }
        public String getBuildspec() {
            return buildspec;
        }
        public void setBuildspec(String buildspec) {
            this.buildspec = buildspec;
        }
        public Map<String, BuildEnvironmentVariable> getEnvironmentVariables() {
            return environmentVariables;
        }
        public void setEnvironmentVariables(Map<String, BuildEnvironmentVariable> environmentVariables) {
            this.environmentVariables = environmentVariables;
        }
        public Duration getCodeBuildTimeout() {
            return codeBuildTimeout;
        }
        public void setCodeBuildTimeout(Duration codeBuildTimeout) {
            this.codeBuildTimeout = codeBuildTimeout;
        }
        public Boolean getPrivilegedMode() {
            return privilegedMode;
        }
        public IVpc getVpc() {
            return vpc;
        }
        public void setVpc(IVpc vpc) {
            this.vpc = vpc;
        }
        public void setPrivilegedMode(Boolean privilegedMode) {
            this.privilegedMode = privilegedMode;
        }
        public List<IManagedPolicy> getAdditionalIamPolicies() {
            return additionalIamPolicies;
        }
        public void setAdditionalIamPolicies(List<IManagedPolicy> additionalIamPolicies) {
            this.additionalIamPolicies = additionalIamPolicies;
        }
        public IRole getRole() {
            return role;
        }
        public void setRole(IRole role) {
            this.role = role;
        }
    }

    public CodeBuildResource(Construct scope, String id, CodeBuildCustomResourceProps props) {
        super(scope, id);

        // Read function code from files
        String respondFunctionCode = loadFile("/respond-function.js.tmpl");
        String startBuildFunctionCode = loadFile("/start-build.js.tmpl");
        String reportBuildFunctionCode = loadFile("/report-build.js.tmpl");

        // Create CodeBuild project
        this.codebuildProject = Project.Builder.create(this, "CodeBuildProject")
            .role(props.getRole())
            .vpc(props.getVpc())
            .projectName("unicornstore-codebuild")
            .subnetSelection(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .environment(BuildEnvironment.builder()
                .buildImage(props.getBuildImage())
                .computeType(props.getComputeType())
                .privileged(props.getPrivilegedMode())
                .build())
            .buildSpec(BuildSpec.fromObjectToYaml(new Yaml().load(props.getBuildspec())))
            .environmentVariables(props.getEnvironmentVariables())
            .timeout(props.getCodeBuildTimeout())
            .build();

        // Add managed policies
        props.getAdditionalIamPolicies().forEach(policy ->
            this.codebuildProject.getRole().addManagedPolicy(policy));

        // Create start build Lambda function
        Function startBuildFunction = Function.Builder.create(this, "StartBuildFunction")
            .code(Code.fromInline(respondFunctionCode + startBuildFunctionCode))
            .handler("index.handler")
            .runtime(Runtime.NODEJS_20_X)
            .timeout(Duration.minutes(1))
            .functionName("unicornstore-codebuild-start")
            .build();

        startBuildFunction.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(Arrays.asList("codebuild:StartBuild"))
            .resources(Arrays.asList(this.codebuildProject.getProjectArn()))
            .build());

        // Create report build Lambda function
        Function reportBuildFunction = Function.Builder.create(this, "ReportBuildFunction")
            .code(Code.fromInline(respondFunctionCode + reportBuildFunctionCode))
            .handler("index.handler")
            .runtime(Runtime.NODEJS_20_X)
            .timeout(Duration.minutes(1))
            .functionName("unicornstore-codebuild-report")
            .build();

        reportBuildFunction.addToRolePolicy(PolicyStatement.Builder.create()
            .actions(Arrays.asList("codebuild:BatchGetBuilds", "codebuild:ListBuildsForProject"))
            .resources(Arrays.asList(this.codebuildProject.getProjectArn()))
            .build());

        // Create EventBridge rule
        Rule buildCompleteRule = Rule.Builder.create(this, "BuildCompleteRule")
            .description("Build complete")
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

        // Create custom resource
        this.customResource = new CustomResource(this, "ClusterStack", CustomResourceProps.builder()
            .serviceToken(startBuildFunction.getFunctionArn())
            .properties(Map.of(
                "ProjectName", this.codebuildProject.getProjectName(),
                "CodeBuildIamRoleArn", this.codebuildProject.getRole().getRoleArn(),
                "ContentHash", calculateMd5(props.getBuildspec())
            ))
            .build());

        this.customResource.getNode().addDependency(buildCompleteRule, reportBuildFunction);
    }

    private String calculateMd5(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] hash = md.digest(input.getBytes("UTF-8"));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    public Project getCodeBuildProject() {
        return this.codebuildProject;
    }
}
