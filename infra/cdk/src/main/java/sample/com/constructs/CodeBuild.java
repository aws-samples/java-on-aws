package sample.com.constructs;

import io.github.cdklabs.cdknag.NagPackSuppression;
import io.github.cdklabs.cdknag.NagSuppressions;
import software.amazon.awscdk.ArnComponents;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.services.codebuild.*;
import software.amazon.awscdk.services.dynamodb.*;
import software.amazon.awscdk.services.events.*;
import software.amazon.awscdk.services.events.targets.LambdaFunction;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.constructs.Construct;

import java.util.ArrayList;
import java.util.Map;
import java.util.List;
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
        private List<software.constructs.IDependable> dependencies;
        private List<PolicyStatement> rolePolicyStatements = List.of();

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
            public Builder dependencies(List<software.constructs.IDependable> dependencies) { props.dependencies = dependencies; return this; }
            public Builder rolePolicyStatements(List<PolicyStatement> rolePolicyStatements) { props.rolePolicyStatements = List.copyOf(rolePolicyStatements); return this; }

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
        public List<software.constructs.IDependable> getDependencies() { return dependencies; }
        public List<PolicyStatement> getRolePolicyStatements() { return rolePolicyStatements; }
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
            .build();
        props.getRolePolicyStatements().forEach(codeBuildRole::addToPolicy);

        // Create Lambda role for CodeBuild Lambda functions
        this.lambdaRole = Role.Builder.create(this, "LambdaRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
            ))
            .build();

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

        String networkInterfaceArn = Stack.of(this).formatArn(ArnComponents.builder()
            .service("ec2")
            .resource("network-interface")
            .resourceName("*")
            .build());
        List<String> subnetArns = props.getVpc().getPrivateSubnets().stream()
            .map(subnet -> Stack.of(this).formatArn(ArnComponents.builder()
                .service("ec2")
                .resource("subnet")
                .resourceName(subnet.getSubnetId())
                .build()))
            .toList();
        List<String> createNetworkInterfaceResources = new ArrayList<>(subnetArns);
        createNetworkInterfaceResources.addAll(codebuildProject.getConnections().getSecurityGroups().stream()
            .map(securityGroup -> Stack.of(this).formatArn(ArnComponents.builder()
                .service("ec2")
                .resource("security-group")
                .resourceName(securityGroup.getSecurityGroupId())
                .build()))
            .toList());
        createNetworkInterfaceResources.add(networkInterfaceArn);

        CfnPolicy vpcPolicy = (CfnPolicy) codebuildProject.getNode()
            .findChild("PolicyDocument").getNode().getDefaultChild();
        vpcPolicy.addPropertyOverride("PolicyDocument.Statement", List.of(
            Map.of(
                "Effect", "Allow",
                "Action", List.of("ec2:CreateNetworkInterface"),
                "Resource", createNetworkInterfaceResources
            ),
            Map.of(
                "Effect", "Allow",
                "Action", List.of("ec2:CreateNetworkInterfacePermission"),
                "Resource", networkInterfaceArn,
                "Condition", Map.of(
                    "StringEquals", Map.of("ec2:AuthorizedService", "codebuild.amazonaws.com"),
                    "ArnEquals", Map.of("ec2:Subnet", subnetArns)
                )
            ),
            Map.of(
                "Effect", "Allow",
                "Action", List.of("ec2:DeleteNetworkInterface"),
                "Resource", "*"
            ),
            Map.of(
                "Effect", "Allow",
                "Action", List.of(
                    "ec2:DescribeDhcpOptions",
                    "ec2:DescribeNetworkInterfaces",
                    "ec2:DescribeSecurityGroups",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeVpcs"
                ),
                "Resource", "*"
            )
        ));
        vpcPolicy.addMetadata("checkov", Map.of(
            "skip", List.of(Map.of(
                "id", "CKV_AWS_111",
                "comment", "CodeBuild requires ec2:DeleteNetworkInterface on wildcard resources because the API authorizes deletion against arn:aws:ec2:region:account:*/*."
            ))
        ));

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("codebuild:StartBuild", "codebuild:BatchGetBuilds"))
            .resources(List.of(codebuildProject.getProjectArn()))
            .build());

        // Create start build Lambda function
        var startLambda = new Lambda(this, "StartLambda",
            "/lambda/codebuild-start.py", props.getProjectName() + "-start", Duration.minutes(2), lambdaRole);
        Function startBuildFunction = startLambda.getFunction();

        // Persist the CloudFormation callback while CodeBuild runs. The start Lambda
        // intentionally does not answer Create/Update requests; the report Lambda
        // sends the response only after a terminal CodeBuild event.
        Table pendingBuilds = Table.Builder.create(this, "PendingBuilds")
            .partitionKey(Attribute.builder()
                .name("BuildId")
                .type(AttributeType.STRING)
                .build())
            .billingMode(BillingMode.PAY_PER_REQUEST)
            .timeToLiveAttribute("ExpiresAt")
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();
        NagSuppressions.addResourceSuppressions(pendingBuilds, List.of(
            new NagPackSuppression.Builder()
                .id("AwsSolutions-DDB3")
                .reason("The table stores short-lived CloudFormation callback state and does not require point-in-time recovery")
                .build()
        ));

        startBuildFunction.addEnvironment("PENDING_TABLE_NAME", pendingBuilds.getTableName());
        pendingBuilds.grantWriteData(startBuildFunction);

        var reportLambda = new Lambda(this, "ReportLambda",
            "/lambda/codebuild-report.py", props.getProjectName() + "-report",
            Duration.minutes(2), lambdaRole);
        Function reportBuildFunction = reportLambda.getFunction();
        reportBuildFunction.addEnvironment("PENDING_TABLE_NAME", pendingBuilds.getTableName());
        pendingBuilds.grantReadWriteData(reportBuildFunction);

        Rule buildCompleteRule = Rule.Builder.create(this, "CompleteRule")
            .description(props.getProjectName() + " build complete")
            .eventPattern(EventPattern.builder()
                .source(List.of("aws.codebuild"))
                .detailType(List.of("CodeBuild Build State Change"))
                .detail(Map.of(
                    "build-status", List.of("SUCCEEDED", "FAILED", "FAULT", "STOPPED", "TIMED_OUT"),
                    "project-name", List.of(this.codebuildProject.getProjectName())
                ))
                .build())
            .targets(List.of(new LambdaFunction(reportBuildFunction)))
            .build();

        this.customResource = CustomResource.Builder.create(this, "Resource")
            .serviceToken(startBuildFunction.getFunctionArn())
            .properties(Map.of(
                "ProjectName", this.codebuildProject.getProjectName(),
                "ContentHash", String.valueOf(System.currentTimeMillis())
            ))
            .build();

        this.customResource.getNode().addDependency(this.codebuildProject);
        this.customResource.getNode().addDependency(vpcPolicy);
        this.customResource.getNode().addDependency(pendingBuilds);
        this.customResource.getNode().addDependency(buildCompleteRule);
        this.customResource.getNode().addDependency(startBuildFunction);
        this.customResource.getNode().addDependency(reportBuildFunction);

        // Add external dependencies (e.g., NAT Gateway, ECR Registry)
        if (props.getDependencies() != null) {
            for (software.constructs.IDependable dep : props.getDependencies()) {
                this.customResource.getNode().addDependency(dep);
            }
        }
    }

    public Project getCodeBuildProject() {
        return this.codebuildProject;
    }

    public CustomResource getCustomResource() {
        return this.customResource;
    }
}