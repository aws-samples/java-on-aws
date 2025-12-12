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
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Ide extends Construct {
    private final SecurityGroup ideSecurityGroup;
    private final SecurityGroup ideInternalSecurityGroup;
    private final Secret ideSecretsManagerPassword;

    public static class IdeProps {
        private String instanceName = "ide";
        private int diskSize = 50;
        private IVpc vpc;
        private IMachineImage machineImage = MachineImage.latestAmazonLinux2023();
        private List<String> instanceTypes = Arrays.asList("m5.xlarge", "m6i.xlarge", "t3.xlarge");
        private List<ISecurityGroup> additionalSecurityGroups = new ArrayList<>();
        private int bootstrapTimeoutMinutes = 30;
        private Role role;
        private Role lambdaRole;

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
            public Builder role(Role role) { props.role = role; return this; }
            public Builder lambdaRole(Role lambdaRole) { props.lambdaRole = lambdaRole; return this; }

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
        public Role getRole() { return role; }
        public Role getLambdaRole() { return lambdaRole; }
    }

    public Ide(final Construct scope, final String id, final IVpc vpc, final Roles roles) {
        this(scope, id, IdeProps.builder()
            .vpc(vpc)
            .role(roles.getWorkshopRole())
            .lambdaRole(roles.getLambdaRole())
            .build());
    }

    public Ide(final Construct scope, final String id, final IdeProps props) {
        super(scope, id);

        String instanceName = props.getInstanceName();

        // Set up wait condition handle for bootstrap completion (needed for User Data)
        var waitHandle = CfnWaitConditionHandle.Builder.create(this, "IdeBootstrapWaitConditionHandle")
            .build();

        // Use static CloudFront prefix list ID (more reliable than Lambda lookup)
        String cloudFrontPrefixListId = "pl-3b927c52"; // CloudFront origin-facing prefix list

        // Create security group for IDE access (CloudFront only)
        this.ideSecurityGroup = SecurityGroup.Builder.create(this, "IdeSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(true)
            .securityGroupName(instanceName + "-cloudfront-ide-sg")
            .description("IDE security group")
            .build();

        ideSecurityGroup.addIngressRule(
            Peer.prefixList(cloudFrontPrefixListId),
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
            .role(props.getRole())
            .instanceProfileName(props.getRole().getRoleName())
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
            .build();

        ideSecretsManagerPassword.grantRead(props.getRole());

        // Create User Data for bootstrap with CloudWatch logging
        var userData = UserData.forLinux();
        String bootstrapScript = loadFile("/bootstrap.sh")
            .replace("${stackName}", Aws.STACK_NAME)
            .replace("${awsRegion}", Aws.REGION)
            .replace("${idePassword}", ideSecretsManagerPassword.secretValueFromJson("password").unsafeUnwrap());
        userData.addCommands(bootstrapScript.split("\n"));

        // Create instance launcher Lambda with multi-AZ and multi-instance-type failover
        var instanceLauncherFunction = Function.Builder.create(this, "IdeInstanceLauncherFunction")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.lambda_handler")
            .code(Code.fromInline(loadFile("/launcher.py")))
            .timeout(Duration.minutes(5))
            .functionName(instanceName + "-launcher")
            .role(props.getLambdaRole())
            .build();

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

        var waitCondition = CfnWaitCondition.Builder.create(this, "IdeBootstrapWaitCondition")
            .count(1)
            .handle(waitHandle.getRef())
            .timeout(String.valueOf(props.getBootstrapTimeoutMinutes() * 60))
            .build();
        waitCondition.getNode().addDependency(ec2InstanceResource);

        // Outputs
        CfnOutput.Builder.create(this, "IdeUrl")
            .value("https://" + distribution.getDistributionDomainName())
            .description("Workshop IDE URL")
            .exportName(instanceName + "-url")
            .build();

        CfnOutput.Builder.create(this, "IdePassword")
            .value(ideSecretsManagerPassword.secretValueFromJson("password").unsafeUnwrap())
            .description("Workshop IDE Password")
            .exportName(instanceName + "-password")
            .build();
    }

    public SecurityGroup getIdeSecurityGroup() {
        return ideSecurityGroup;
    }

    public SecurityGroup getIdeInternalSecurityGroup() {
        return ideInternalSecurityGroup;
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
}