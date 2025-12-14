package sample.com.constructs;

import software.amazon.awscdk.Aws;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnWaitCondition;
import software.amazon.awscdk.CfnWaitConditionHandle;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.cloudfront.AllowedMethods;
import software.amazon.awscdk.services.cloudfront.BehaviorOptions;
import software.amazon.awscdk.services.cloudfront.CachePolicy;
import software.amazon.awscdk.services.cloudfront.Distribution;
import software.amazon.awscdk.services.cloudfront.HttpVersion;
import software.amazon.awscdk.services.cloudfront.OriginProtocolPolicy;
import software.amazon.awscdk.services.cloudfront.OriginRequestPolicy;
import software.amazon.awscdk.services.cloudfront.ViewerProtocolPolicy;
import software.amazon.awscdk.services.cloudfront.origins.HttpOrigin;
import software.amazon.awscdk.services.cloudfront.origins.HttpOriginProps;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.secretsmanager.Secret;
import software.amazon.awscdk.services.secretsmanager.SecretStringGenerator;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import org.json.JSONObject;

public class Ide extends Construct {
    private final SecurityGroup ideSecurityGroup;
    private final SecurityGroup ideInternalSecurityGroup;
    private final Secret ideSecretsManagerPassword;
    private final Role ideRole;
    private final Role lambdaRole;
    private CustomResource passwordResource;

    public static class IdeProps {
        private String instanceName = "ide";
        private int diskSize = 50;
        private IVpc vpc;
        private IMachineImage machineImage = MachineImage.latestAmazonLinux2023();
        private List<String> instanceTypes = Arrays.asList("m5.xlarge", "m6i.xlarge", "t3.xlarge");
        private List<ISecurityGroup> additionalSecurityGroups = new ArrayList<>();
        private int bootstrapTimeoutMinutes = 30;
        private String gitBranch = "main";
        private String templateType = "base";

        public static IdeProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private IdeProps props = new IdeProps();

            public Builder instanceName(String instanceName) { props.instanceName = instanceName; return this; }
            public Builder diskSize(int diskSize) { props.diskSize = diskSize; return this; }
            public Builder vpc(IVpc vpc) { props.vpc = vpc; return this; }
            public Builder machineImage(IMachineImage machineImage) { props.machineImage = machineImage; return this; }
            public Builder instanceTypes(List<String> instanceTypes) { props.instanceTypes = instanceTypes; return this; }
            public Builder additionalSecurityGroups(List<ISecurityGroup> additionalSecurityGroups) { props.additionalSecurityGroups = additionalSecurityGroups; return this; }
            public Builder bootstrapTimeoutMinutes(int bootstrapTimeoutMinutes) { props.bootstrapTimeoutMinutes = bootstrapTimeoutMinutes; return this; }
            public Builder gitBranch(String gitBranch) { props.gitBranch = gitBranch; return this; }
            public Builder templateType(String templateType) { props.templateType = templateType; return this; }
            public IdeProps build() { return props; }
        }

        // Getters
        public String getInstanceName() { return instanceName; }
        public int getDiskSize() { return diskSize; }
        public IVpc getVpc() { return vpc; }
        public IMachineImage getMachineImage() { return machineImage; }
        public List<String> getInstanceTypes() { return instanceTypes; }
        public List<ISecurityGroup> getAdditionalSecurityGroups() { return additionalSecurityGroups; }
        public int getBootstrapTimeoutMinutes() { return bootstrapTimeoutMinutes; }
        public String getGitBranch() { return gitBranch; }
        public String getTemplateType() { return templateType; }
    }

    public Ide(final Construct scope, final String id, final IVpc vpc) {
        this(scope, id, IdeProps.builder()
            .vpc(vpc)
            .build());
    }

    public Ide(final Construct scope, final String id, final IdeProps props) {
        super(scope, id);

        String instanceName = props.getInstanceName();

        // Create workshop role for IDE instances
        this.ideRole = Role.Builder.create(this, "IdeRole")
            .roleName("ide-user")
            .assumedBy(ServicePrincipal.Builder.create("ec2.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("ReadOnlyAccess"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
                ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy")
            ))
            .build();

        // Add CloudFormation signaling permissions
        PolicyStatement cfnSignalPermissions = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "cloudformation:SignalResource"
            ))
            .resources(List.of("*"))
            .build();

        ideRole.addToPolicy(cfnSignalPermissions);

        // Load additional IAM policy from file
        var policyDocumentJson = loadFile("/iam-policy.json");
        if (policyDocumentJson != null) {
            var policyDocument = PolicyDocument.fromJson(new JSONObject(policyDocumentJson).toMap());
            var policy = ManagedPolicy.Builder.create(this, "WorkshopIdeUserPolicy")
                .document(policyDocument)
                .build();
            ideRole.addManagedPolicy(policy);
        }

        // Create Lambda role for IDE Lambda functions
        this.lambdaRole = Role.Builder.create(this, "IdeLambdaRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
            ))
            .build();

        // Add specific permissions for Lambda functions
        PolicyStatement lambdaPermissions = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "ec2:DescribeManagedPrefixLists",
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:CreateTags",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeSubnets",
                "iam:PassRole",
                "ssm:DescribeInstanceInformation",
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ))
            .resources(List.of("*"))
            .build();

        lambdaRole.addToPolicy(lambdaPermissions);

        // Set up wait condition handle for bootstrap completion (needed for User Data)
        var waitHandle = CfnWaitConditionHandle.Builder.create(this, "BootstrapWaitConditionHandle")
            .build();

        // Create CloudFront prefix list lookup Lambda function
        var prefixListLookup = new Lambda(this, "PrefixListLookup",
            "/lambda/cloudfront-prefix-lookup.py", "ide-cloudfront-prefix-lookup", Duration.minutes(3), lambdaRole);
        var prefixListFunction = prefixListLookup.getFunction();

        // Add EC2 permissions for prefix list lookup
        PolicyStatement prefixListPermissions = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ec2:DescribeManagedPrefixLists"))
            .resources(List.of("*"))
            .build();

        lambdaRole.addToPolicy(prefixListPermissions);

        // Create custom resource to get CloudFront prefix list ID
        var prefixListResource = CustomResource.Builder.create(this, "PrefixListResource")
            .serviceToken(prefixListFunction.getFunctionArn())
            .build();

        // Create security group for IDE access (CloudFront only)
        this.ideSecurityGroup = SecurityGroup.Builder.create(this, "IdeSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(true)
            .securityGroupName(instanceName + "-cloudfront-ide-sg")
            .description("IDE security group")
            .build();

        ideSecurityGroup.addIngressRule(
            Peer.prefixList(prefixListResource.getAttString("PrefixListId")),
            Port.tcp(80),
            "HTTP from CloudFront only"
        );

        // Internal security group for VPC communication
        this.ideInternalSecurityGroup = SecurityGroup.Builder.create(this, "IdeInternalSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(false)
            .securityGroupName(instanceName + "-internal-sg")
            .description("IDE internal security group")
            .build();

        ideInternalSecurityGroup.getConnections().allowInternally(
            Port.allTraffic(),
            "Allow all internal traffic"
        );

        // Create instance profile
        var instanceProfile = InstanceProfile.Builder.create(this, "IdeInstanceProfile")
            .role(ideRole)
            .instanceProfileName(ideRole.getRoleName())
            .build();

        // Create Elastic IP
        var elasticIP = CfnEIP.Builder.create(this, "IdeElasticIP")
            .domain("vpc")
            .build();

        // Get public subnets
        var publicSubnets = props.getVpc().selectSubnets(SubnetSelection.builder()
            .subnetType(SubnetType.PUBLIC)
            .build());

        // Build security group IDs list (including additional security groups)
        List<String> securityGroupIds = new ArrayList<>();
        securityGroupIds.add(ideSecurityGroup.getSecurityGroupId());
        securityGroupIds.add(ideInternalSecurityGroup.getSecurityGroupId());
        props.getAdditionalSecurityGroups().forEach(sg -> securityGroupIds.add(sg.getSecurityGroupId()));

        // Create password secret
        this.ideSecretsManagerPassword = Secret.Builder.create(this, "IdePasswordSecret")
            .generateSecretString(SecretStringGenerator.builder()
                .excludePunctuation(true)
                .passwordLength(32)
                .generateStringKey("password")
                .includeSpace(false)
                .secretStringTemplate("{\"password\":\"\"}")
                .excludeCharacters("\"@/\\\\")
                .build())
            .secretName(instanceName + "-password")
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        ideSecretsManagerPassword.grantRead(ideRole);

        // Create User Data for bootstrap with CloudWatch logging
        var userData = UserData.forLinux();
        String gitBranch = props.getGitBranch();
        String templateType = props.getTemplateType();

        // Load UserData from external template file and substitute variables
        String userDataTemplate = loadFile("/userdata.sh");
        String userDataContent = userDataTemplate
            .replace("${GIT_BRANCH}", gitBranch)
            .replace("${AWS_REGION}", Aws.REGION)
            .replace("${TEMPLATE_TYPE}", templateType)
            .replace("${WAIT_CONDITION_HANDLE_URL}", waitHandle.getRef());

        userData.addCommands(userDataContent);

        // Create instance launcher Lambda with multi-AZ and multi-instance-type failover
        var instanceLauncher = new Lambda(this, "InstanceLauncher",
            "/lambda/ec2-launcher.py", "ide-ec2-launcher", Duration.minutes(5), lambdaRole);
        var instanceLauncherFunction = instanceLauncher.getFunction();

        // Create EC2 instance via Custom Resource with intelligent failover
        var ec2InstanceResource = CustomResource.Builder.create(this, "IdeEC2InstanceResource")
            .serviceToken(instanceLauncherFunction.getFunctionArn())
            .properties(Map.of(
                "SubnetIds", String.join(",", publicSubnets.getSubnetIds()),
                "InstanceTypes", String.join(",", props.getInstanceTypes()),
                "ImageId", props.getMachineImage().getImage(this).getImageId(),
                "SecurityGroupIds", String.join(",", securityGroupIds),
                "IamInstanceProfileArn", instanceProfile.getInstanceProfileArn(),
                "VolumeSize", String.valueOf(props.getDiskSize()),
                "InstanceName", instanceName,
                "UserData", Fn.base64(userData.render())
            ))
            .build();

        String instanceId = ec2InstanceResource.getAttString("InstanceId");

        // Associate Elastic IP with the instance
        var ipAssociation = CfnEIPAssociation.Builder.create(this, "IdeEipAssociation")
            .allocationId(elasticIP.getAttrAllocationId())
            .instanceId(instanceId)
            .build();

        // Create public DNS name from EIP
        String publicDnsName = Fn.join("", List.of(
            "ec2-",
            Fn.select(0, Fn.split(".", elasticIP.getAttrPublicIp())),
            "-",
            Fn.select(1, Fn.split(".", elasticIP.getAttrPublicIp())),
            "-",
            Fn.select(2, Fn.split(".", elasticIP.getAttrPublicIp())),
            "-",
            Fn.select(3, Fn.split(".", elasticIP.getAttrPublicIp())),
            ".compute-1.amazonaws.com"
        ));

        // Create CloudFront distribution
        var distribution = Distribution.Builder.create(this, "IdeDistribution")
            .defaultBehavior(BehaviorOptions.builder()
                .origin(new HttpOrigin(publicDnsName,
                    HttpOriginProps.builder()
                        .protocolPolicy(OriginProtocolPolicy.HTTP_ONLY)
                        .httpPort(80)
                        .build()))
                .allowedMethods(AllowedMethods.ALLOW_ALL)
                .cachePolicy(CachePolicy.CACHING_DISABLED)
                .originRequestPolicy(OriginRequestPolicy.ALL_VIEWER)
                .viewerProtocolPolicy(ViewerProtocolPolicy.ALLOW_ALL)
                .build())
            .httpVersion(HttpVersion.HTTP2)
            .build();

        distribution.applyRemovalPolicy(RemovalPolicy.DESTROY);
        distribution.getNode().addDependency(ipAssociation);

        var waitCondition = CfnWaitCondition.Builder.create(this, "BootstrapWaitCondition")
            .count(1)
            .handle(waitHandle.getRef())
            .timeout(String.valueOf(props.getBootstrapTimeoutMinutes() * 60))
            .build();
        waitCondition.getNode().addDependency(ec2InstanceResource);

        // CloudFront doesn't need to wait for bootstrap - it's just infrastructure

        // Outputs - these should only be created if bootstrap succeeds
        var ideUrlOutput = CfnOutput.Builder.create(this, "Url")
            .value("https://" + distribution.getDistributionDomainName())
            .description("Workshop IDE Url")
            .exportName(instanceName + "-url")
            .build();
        ideUrlOutput.getNode().addDependency(waitCondition);

        var idePasswordOutput = CfnOutput.Builder.create(this, "Password")
            .value(getIdePassword(instanceName))
            .description("Workshop IDE Password")
            .exportName(instanceName + "-password")
            .build();
        idePasswordOutput.getNode().addDependency(waitCondition);
    }

    public SecurityGroup getIdeSecurityGroup() {
        return ideSecurityGroup;
    }

    public SecurityGroup getIdeInternalSecurityGroup() {
        return ideInternalSecurityGroup;
    }

    public Role getIdeRole() {
        return ideRole;
    }

    /**
     * Helper method to load file content from resources
     */
    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    private String getIdePassword(String instanceName) {
        if (passwordResource == null) {
            Function passwordFunction = Function.Builder.create(this, "PasswordExporterFunction")
                .code(Code.fromInline(loadFile("/lambda/password-exporter.py")))
                .handler("index.lambda_handler")
                .runtime(Runtime.PYTHON_3_13)
                .timeout(Duration.minutes(3))
                .functionName(instanceName + "-password-exporter")
                .build();

            ideSecretsManagerPassword.grantRead(passwordFunction);

            passwordResource = CustomResource.Builder.create(this, "PasswordExporter")
                .serviceToken(passwordFunction.getFunctionArn())
                .properties(Map.of(
                    "PasswordName", this.ideSecretsManagerPassword.getSecretName()
                ))
                .build();
        }

        return passwordResource.getAttString("password");
    }
}