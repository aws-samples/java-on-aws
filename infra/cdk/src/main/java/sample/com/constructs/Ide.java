package sample.com.constructs;

import software.amazon.awscdk.Aws;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnWaitCondition;
import software.amazon.awscdk.CfnWaitConditionHandle;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Stack;
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
    private final String prefix;
    private CustomResource passwordResource;

    /**
     * Architecture enum for IDE instances.
     * Determines instance types and AMI selection.
     */
    public enum IdeArch {
        ARM64("arm64", "aarch64"),
        X86_64_AMD("x86_64", "x86_64"),
        X86_64_INTEL("x86_64", "x86_64");

        private final String awsValue;
        private final String unameValue;

        IdeArch(String awsValue, String unameValue) {
            this.awsValue = awsValue;
            this.unameValue = unameValue;
        }

        public String getAwsValue() { return awsValue; }
        public String getUnameValue() { return unameValue; }
    }

    /**
     * IDE type enum for selecting between code-server and AWS Code Editor.
     */
    public enum IdeType {
        CODE_EDITOR("code-editor"),
        VSCODE("vscode");

        private final String scriptName;

        IdeType(String scriptName) {
            this.scriptName = scriptName;
        }

        public String getScriptName() { return scriptName; }
    }

    public static class IdeProps {
        private String prefix = "workshop";
        private String instanceName = "ide";
        private int diskSize = 50;
        private IVpc vpc;
        private IdeArch ideArch = IdeArch.X86_64_AMD;
        private IdeType ideType = IdeType.CODE_EDITOR;
        private List<ISecurityGroup> additionalSecurityGroups = new ArrayList<>();
        private int bootstrapTimeoutMinutes = 30;
        private String gitBranch = "main";
        private String templateType = "base";
        private String workshopId = "base";
        private Role ideRole;

        // Architecture-specific instance type lists
        private static final List<String> ARM64_INSTANCE_TYPES =
            Arrays.asList("m7g.xlarge", "m6g.xlarge");
        private static final List<String> X86_64_AMD_INSTANCE_TYPES =
            Arrays.asList("m6a.xlarge", "m7a.xlarge");
        private static final List<String> X86_64_INTEL_INSTANCE_TYPES =
            Arrays.asList("m6i.xlarge", "m5.xlarge", "m7i.xlarge", "m7i-flex.xlarge");

        public static IdeProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private IdeProps props = new IdeProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public Builder instanceName(String instanceName) { props.instanceName = instanceName; return this; }
            public Builder diskSize(int diskSize) { props.diskSize = diskSize; return this; }
            public Builder vpc(IVpc vpc) { props.vpc = vpc; return this; }
            public Builder ideArch(IdeArch ideArch) { props.ideArch = ideArch; return this; }
            public Builder ideType(IdeType ideType) { props.ideType = ideType; return this; }
            public Builder additionalSecurityGroups(List<ISecurityGroup> additionalSecurityGroups) { props.additionalSecurityGroups = additionalSecurityGroups; return this; }
            public Builder bootstrapTimeoutMinutes(int bootstrapTimeoutMinutes) { props.bootstrapTimeoutMinutes = bootstrapTimeoutMinutes; return this; }
            public Builder gitBranch(String gitBranch) { props.gitBranch = gitBranch; return this; }
            public Builder templateType(String templateType) { props.templateType = templateType; return this; }
            public Builder workshopId(String workshopId) { props.workshopId = workshopId; return this; }
            public Builder ideRole(Role ideRole) { props.ideRole = ideRole; return this; }
            public IdeProps build() { return props; }
        }

        // Getters
        public String getPrefix() { return prefix; }
        public String getInstanceName() { return instanceName; }
        public int getDiskSize() { return diskSize; }
        public IVpc getVpc() { return vpc; }
        public IdeArch getIdeArch() { return ideArch; }
        public IdeType getIdeType() { return ideType; }

        public IMachineImage getMachineImage() {
            return ideArch == IdeArch.ARM64
                ? MachineImage.latestAmazonLinux2023(AmazonLinux2023ImageSsmParameterProps.builder()
                    .cpuType(AmazonLinuxCpuType.ARM_64).build())
                : MachineImage.latestAmazonLinux2023();
        }

        public List<String> getInstanceTypes() {
            return switch (ideArch) {
                case ARM64 -> ARM64_INSTANCE_TYPES;
                case X86_64_AMD -> X86_64_AMD_INSTANCE_TYPES;
                case X86_64_INTEL -> X86_64_INTEL_INSTANCE_TYPES;
            };
        }

        public List<ISecurityGroup> getAdditionalSecurityGroups() { return additionalSecurityGroups; }
        public int getBootstrapTimeoutMinutes() { return bootstrapTimeoutMinutes; }
        public String getGitBranch() { return gitBranch; }
        public String getTemplateType() { return templateType; }
        public String getWorkshopId() { return workshopId; }
        public Role getIdeRole() { return ideRole; }
    }

    public Ide(final Construct scope, final String id, final IVpc vpc) {
        this(scope, id, IdeProps.builder()
            .vpc(vpc)
            .build());
    }

    public Ide(final Construct scope, final String id, final IdeProps props) {
        super(scope, id);

        String instanceName = props.getInstanceName();
        String prefix = props.getPrefix();
        this.prefix = prefix;

        // Create workshop role for IDE instances if not provided
        if (props.getIdeRole() == null) {
            props.ideRole = Role.Builder.create(this, "Role")
                .roleName(prefix + "-ide-user")
                .assumedBy(ServicePrincipal.Builder.create("ec2.amazonaws.com").build())
                .managedPolicies(List.of(
                    ManagedPolicy.fromAwsManagedPolicyName("ReadOnlyAccess"),
                    ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
                    ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy")
                ))
                .build();
        }
        this.ideRole = props.getIdeRole();

        // Load IAM policy: base template uses AdministratorAccess, others use iam-policy.json
        if ("base".equals(props.getTemplateType())) {
            this.ideRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess"));
        } else {
            String policyDocumentJson = loadFile("/iam-policy.json")
                .replace("{{.AccountId}}", Aws.ACCOUNT_ID);
            var policyDocument = PolicyDocument.fromJson(new JSONObject(policyDocumentJson).toMap());
            var policy = ManagedPolicy.Builder.create(this, "UserPolicy")
                .document(policyDocument)
                .build();
            this.ideRole.addManagedPolicy(policy);

            if ("java-spring-ai-agents".equals(props.getTemplateType())
                || "java-ai-agents".equals(props.getTemplateType())
                || "java-ai-agents-advanced".equals(props.getTemplateType())) {
                String agentCoreManagedToolsPolicyJson = loadFile("/agentcore-managed-tools-policy.json");
                var agentCoreManagedToolsPolicyDocument = PolicyDocument.fromJson(
                    new JSONObject(agentCoreManagedToolsPolicyJson).toMap());
                var agentCoreManagedToolsPolicy = ManagedPolicy.Builder.create(this, "AgentCoreManagedToolsPolicy")
                    .document(agentCoreManagedToolsPolicyDocument)
                    .build();
                this.ideRole.addManagedPolicy(agentCoreManagedToolsPolicy);
            }

            if ("java-ai-agents".equals(props.getTemplateType())
                || "java-ai-agents-advanced".equals(props.getTemplateType())) {
                String agentCoreIdentityPolicyJson = loadFile("/agentcore-identity-policy.json")
                    .replace("{{.AccountId}}", Aws.ACCOUNT_ID);
                var agentCoreIdentityPolicyDocument = PolicyDocument.fromJson(
                    new JSONObject(agentCoreIdentityPolicyJson).toMap());
                var agentCoreIdentityPolicy = ManagedPolicy.Builder.create(this, "AgentCoreIdentityPolicy")
                    .document(agentCoreIdentityPolicyDocument)
                    .build();
                this.ideRole.addManagedPolicy(agentCoreIdentityPolicy);
            }

            // Create permissions boundary for roles created by workshop scripts
            String boundaryJson = loadFile("/workshop-boundary.json")
                .replace("{{.AccountId}}", Aws.ACCOUNT_ID);
            var boundaryDocument = PolicyDocument.fromJson(new JSONObject(boundaryJson).toMap());
            ManagedPolicy.Builder.create(this, "WorkshopBoundary")
                .managedPolicyName("workshop-boundary")
                .document(boundaryDocument)
                .build();
        }

        // Create Lambda role for IDE Lambda functions
        this.lambdaRole = Role.Builder.create(this, "LambdaRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
            ))
            .build();

        // Add specific permissions for Lambda functions
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "ec2:DescribeManagedPrefixLists",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeSubnets"
            ))
            .resources(List.of("*"))
            .build());

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ec2:RunInstances"))
            .resources(List.of(
                "arn:aws:ec2:*::image/*",
                "arn:aws:ec2:*:*:instance/*",
                "arn:aws:ec2:*:*:network-interface/*",
                "arn:aws:ec2:*:*:security-group/*",
                "arn:aws:ec2:*:*:subnet/*",
                "arn:aws:ec2:*:*:volume/*"
            ))
            .build());

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ec2:CreateTags"))
            .resources(List.of("arn:aws:ec2:*:*:instance/*"))
            .conditions(Map.of(
                "StringEquals", Map.of(
                    "ec2:CreateAction", "RunInstances",
                    "aws:RequestTag/Workshop", "true"
                )
            ))
            .build());

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ec2:TerminateInstances"))
            .resources(List.of("arn:aws:ec2:*:*:instance/*"))
            .conditions(Map.of("StringEquals", Map.of("ec2:ResourceTag/Workshop", "true")))
            .build());

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("iam:PassRole"))
            .resources(List.of(this.ideRole.getRoleArn()))
            .conditions(Map.of("StringEquals", Map.of("iam:PassedToService", "ec2.amazonaws.com")))
            .build());

        // Set up wait condition handle for bootstrap completion (needed for User Data)
        var waitHandle = CfnWaitConditionHandle.Builder.create(this, "WaitConditionHandle")
            .build();

        // Create CloudFront prefix list lookup Lambda function
        var prefixListLookup = new Lambda(this, "PrefixListLookup",
            "/lambda/cloudfront-prefix-lookup.py", prefix + "-ide-prefixlist", Duration.minutes(3), lambdaRole);
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
        this.ideSecurityGroup = SecurityGroup.Builder.create(this, "SecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(true)
            .securityGroupName(prefix + "-ide-cloudfront-sg")
            .description("IDE security group")
            .build();

        ideSecurityGroup.addIngressRule(
            Peer.prefixList(prefixListResource.getAttString("PrefixListId")),
            Port.tcp(80),
            "HTTP from CloudFront only"
        );

        // Internal security group for VPC communication
        this.ideInternalSecurityGroup = SecurityGroup.Builder.create(this, "InternalSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(false)
            .securityGroupName(prefix + "-ide-internal-sg")
            .description("IDE internal security group")
            .build();

        ideInternalSecurityGroup.getConnections().allowInternally(
            Port.allTraffic(),
            "Allow all internal traffic"
        );

        // Create instance profile
        var instanceProfile = InstanceProfile.Builder.create(this, "InstanceProfile")
            .role(this.ideRole)
            .instanceProfileName(prefix + "-ide-instance-profile")
            .build();

        // Create Elastic IP
        var elasticIP = CfnEIP.Builder.create(this, "ElasticIP")
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
        this.ideSecretsManagerPassword = Secret.Builder.create(this, "PasswordSecret")
            .generateSecretString(SecretStringGenerator.builder()
                .excludePunctuation(true)
                .passwordLength(32)
                .generateStringKey("password")
                .includeSpace(false)
                .secretStringTemplate("{\"password\":\"\"}")
                .excludeCharacters("\"@/\\\\")
                .build())
            .secretName(prefix + "-ide-password")
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        ideSecretsManagerPassword.grantRead(this.ideRole);

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
            .replace("${WORKSHOP_ID}", props.getWorkshopId())
            .replace("${WORKSHOP_STACK_NAME}", Aws.STACK_NAME)
            .replace("${WORKSHOP_DEPLOYMENT_ID}", Stack.of(this).getStackId())
            .replace("${ARCH}", props.getIdeArch().getUnameValue())
            .replace("${IDE_TYPE}", props.getIdeType().getScriptName())
            .replace("${WAIT_CONDITION_HANDLE_URL}", waitHandle.getRef())
            .replace("${PREFIX}", prefix);

        userData.addCommands(userDataContent);

        // Create instance launcher Lambda with multi-AZ and multi-instance-type failover
        var instanceLauncher = new Lambda(this, "InstanceLauncher",
            "/lambda/ec2-launcher.py", prefix + "-ide-launcher", Duration.minutes(5), lambdaRole);
        var instanceLauncherFunction = instanceLauncher.getFunction();

        // Create EC2 instance via Custom Resource with intelligent failover
        var ec2InstanceResource = CustomResource.Builder.create(this, "EC2InstanceResource")
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
        var ipAssociation = CfnEIPAssociation.Builder.create(this, "EipAssociation")
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
        var distribution = Distribution.Builder.create(this, "Distribution")
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

        var waitCondition = CfnWaitCondition.Builder.create(this, "WaitCondition")
            .count(1)
            .handle(waitHandle.getRef())
            .timeout(String.valueOf(props.getBootstrapTimeoutMinutes() * 60))
            .build();
        waitCondition.getNode().addDependency(ec2InstanceResource);

        // Build URL based on IDE type
        String ideUrl;
        if (props.getIdeType() == IdeType.CODE_EDITOR) {
            // Token-based URL for Code Editor (seamless Workshop Studio access)
            ideUrl = "https://" + distribution.getDistributionDomainName() +
                     "/?folder=/home/ec2-user/environment&tkn=" + getIdePassword(instanceName);
        } else {
            // Standard URL for code-server (password entered via login page)
            ideUrl = "https://" + distribution.getDistributionDomainName();
        }

        // Create outputs at stack level with stable logical IDs for Workshop Studio
        var stack = software.amazon.awscdk.Stack.of(this);
        CfnOutput.Builder.create(stack, "IdeUrl")
            .value(ideUrl)
            .description("Workshop IDE Url")
            .exportName(instanceName + "-url")
            .build();

        var idePasswordOutput = CfnOutput.Builder.create(stack, "IdePassword")
            .value(getIdePassword(instanceName))
            .description("Workshop IDE Password")
            .exportName(instanceName + "-password")
            .build();
        idePasswordOutput.getNode().addDependency(ideSecretsManagerPassword);
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
            var resource = getClass().getResource(filePath);
            if (resource == null) {
                throw new RuntimeException("Resource file not found: " + filePath);
            }
            return Files.readString(Path.of(resource.getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    private String getIdePassword(String instanceName) {
        if (passwordResource == null) {
            Function passwordFunction = Function.Builder.create(this, "PasswordFunction")
                .code(Code.fromInline(loadFile("/lambda/password-exporter.py")))
                .handler("index.lambda_handler")
                .runtime(Runtime.PYTHON_3_13)
                .timeout(Duration.minutes(3))
                .functionName(prefix + "-ide-password")
                .build();

            ideSecretsManagerPassword.grantRead(passwordFunction);

            passwordResource = CustomResource.Builder.create(this, "PasswordResource")
                .serviceToken(passwordFunction.getFunctionArn())
                .properties(Map.of(
                    "PasswordName", this.ideSecretsManagerPassword.getSecretName()
                ))
                .build();
        }

        return passwordResource.getAttString("password");
    }
}