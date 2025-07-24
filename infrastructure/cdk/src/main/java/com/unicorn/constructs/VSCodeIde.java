package com.unicorn.constructs;

import software.amazon.awscdk.*;
// import software.amazon.awscdk.services.cloudfront.AddBehaviorOptions;
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
import software.amazon.awscdk.services.ec2.BlockDevice;
import software.amazon.awscdk.services.ec2.BlockDeviceVolume;
import software.amazon.awscdk.services.ec2.CfnEIP;
import software.amazon.awscdk.services.ec2.CfnEIPAssociation;
import software.amazon.awscdk.services.ec2.EbsDeviceOptions;
import software.amazon.awscdk.services.ec2.EbsDeviceVolumeType;
import software.amazon.awscdk.services.ec2.IMachineImage;
import software.amazon.awscdk.services.ec2.ISecurityGroup;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.Instance;
import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.ec2.MachineImage;
import software.amazon.awscdk.services.ec2.Peer;
import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.secretsmanager.Secret;
import software.amazon.awscdk.services.secretsmanager.SecretStringGenerator;
import software.amazon.awscdk.services.ssm.CfnDocument;

import software.constructs.Construct;
import org.json.JSONObject;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class VSCodeIde extends Construct {

    private CustomResource passwordResource;
    private final Secret ideSecretsManagerPassword;
    private final SecurityGroup ideInternalSecurityGroup;

    public static class VSCodeIdeProps {
        private String instanceName = "ide";
        private String bootstrapScript = "echo bootstrapScript was not provided";
        private int diskSize = 50;
        private IVpc vpc;
        private String availabilityZone;
        private IMachineImage machineImage = MachineImage.latestAmazonLinux2023();
        private InstanceType instanceType = InstanceType.of(InstanceClass.T3, InstanceSize.MEDIUM);
        private String codeServerVersion = "4.101.2";
        private List<IManagedPolicy> additionalIamPolicies = new ArrayList<>();
        private List<ISecurityGroup> additionalSecurityGroups = new ArrayList<>();
        private int bootstrapTimeoutMinutes = 30;
        private boolean enableGitea = false;
        private String splashUrl = "";
        private String readmeUrl = "";
        private String environmentContentsZip = "";
        private List<String> extensions = new ArrayList<>();
        private boolean terminalOnStartup = true;
        private Role role;
        private String additionalIamPolicyPath = "/iam-policy.json";
        private int appPort = 0;

        public String getInstanceName() { return instanceName; }
        public void setInstanceName(String instanceName) { this.instanceName = instanceName; }

        public String getBootstrapScript() { return bootstrapScript; }
        public void setBootstrapScript(String bootstrapScript) { this.bootstrapScript = bootstrapScript; }

        public int getDiskSize() { return diskSize; }
        public void setDiskSize(int diskSize) { this.diskSize = diskSize; }

        public IVpc getVpc() { return vpc; }
        public void setVpc(IVpc vpc) { this.vpc = vpc; }

        public String getAvailabilityZone() { return availabilityZone; }
        public void setAvailabilityZone(String availabilityZone) { this.availabilityZone = availabilityZone; }

        public IMachineImage getMachineImage() { return machineImage; }
        public void setMachineImage(IMachineImage machineImage) { this.machineImage = machineImage; }

        public InstanceType getInstanceType() { return instanceType; }
        public void setInstanceType(InstanceType instanceType) { this.instanceType = instanceType; }

        public String getCodeServerVersion() { return codeServerVersion; }
        public void setCodeServerVersion(String codeServerVersion) { this.codeServerVersion = codeServerVersion; }

        public List<IManagedPolicy> getAdditionalIamPolicies() { return additionalIamPolicies; }
        public void setAdditionalIamPolicies(List<IManagedPolicy> additionalIamPolicies) { this.additionalIamPolicies = additionalIamPolicies; }

        public List<ISecurityGroup> getAdditionalSecurityGroups() { return additionalSecurityGroups; }
        public void setAdditionalSecurityGroups(List<ISecurityGroup> additionalSecurityGroups) { this.additionalSecurityGroups = additionalSecurityGroups; }

        public int getBootstrapTimeoutMinutes() { return bootstrapTimeoutMinutes; }
        public void setBootstrapTimeoutMinutes(int bootstrapTimeoutMinutes) { this.bootstrapTimeoutMinutes = bootstrapTimeoutMinutes; }

        public boolean isEnableGitea() { return enableGitea; }
        public void setEnableGitea(boolean enableGitea) { this.enableGitea = enableGitea; }

        public String getSplashUrl() { return splashUrl; }
        public void setSplashUrl(String splashUrl) { this.splashUrl = splashUrl; }

        public String getReadmeUrl() { return readmeUrl; }
        public void setReadmeUrl(String readmeUrl) { this.readmeUrl = readmeUrl; }

        public String getEnvironmentContentsZip() { return environmentContentsZip; }
        public void setEnvironmentContentsZip(String environmentContentsZip) { this.environmentContentsZip = environmentContentsZip; }

        public List<String> getExtensions() { return extensions; }
        public void setExtensions(List<String> extensions) { this.extensions = extensions; }

        public boolean isTerminalOnStartup() { return terminalOnStartup; }
        public void setTerminalOnStartup(boolean terminalOnStartup) { this.terminalOnStartup = terminalOnStartup; }

        public Role getRole() { return role; }
        public void setRole(Role role) { this.role = role; }

        public String getAdditionalIamPolicyPath() { return additionalIamPolicyPath; }
        public void setAdditionalIamPolicyPath(String additionalIamPolicyPath) { this.additionalIamPolicyPath = additionalIamPolicyPath; }

        public int getAppPort() { return appPort; }
        public void setAppPort(int appPort) { this.appPort = appPort; }
    }

    public VSCodeIde(final Construct scope, final String id, final VSCodeIdeProps props) {
        super(scope, id);

        // Check VPC
        if (props.getVpc() == null) {
            throw new IllegalArgumentException("VPC must be provided in the properties and cannot be null");
        }

        if (props.getAvailabilityZone() == null) {
            props.setAvailabilityZone(props.getVpc().getAvailabilityZones().get(0));
        }

        // Check IAM role
        if (props.getRole() == null) {
            props.setRole(Role.Builder.create(this, "IdeRole")
                .assumedBy(new ServicePrincipal("ec2.amazonaws.com"))
                .roleName(props.getInstanceName() + "-user")
                .build());
        }

        // props.getRole().addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess"));
        props.getRole().addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("ReadOnlyAccess"));
        props.getRole().addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"));

        var filePath = props.getAdditionalIamPolicyPath();
        try {
            var policyPath = Path.of(getClass().getResource(filePath).toURI());
            if (Files.exists(policyPath)) {
                var jsonPolicy = loadFile(filePath);
                // AccountId dynamisch einsetzen
                String accountId = Stack.of(this).getAccount();
                String replaced = jsonPolicy.replace("{{.AccountId}}", accountId);
                var policyDoc = new JSONObject(replaced).toMap();

                CfnManagedPolicy.Builder.create(this, "WorkshopIdeUserPolicy")
                        .policyDocument(policyDoc)
                        .managedPolicyName("WorkshopIdeUserPolicy")
                        .roles(List.of(props.getRole().getRoleName()))
                        .build();
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to read or parse IAM policy file: " + filePath, e);
        }

        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss");
        String timestamp = LocalDateTime.now().format(formatter);

        // Set up logging
        LogGroup logGroup = LogGroup.Builder.create(this, "IdeLogGroup")
            .retention(RetentionDays.ONE_WEEK)
            .logGroupName(props.getInstanceName() + "-bootstrap-log-" + timestamp)
            .build();
        logGroup.grantWrite(props.getRole());

        // Create prefix List of CloudFront IP for EC2 instance segurity Group
        Function prefixListFunction = Function.Builder.create(this, "IdePrefixListFunction")
            .code(Code.fromInline(loadFile("/prefix-lambda.py")))
            .handler("index.lambda_handler")
            .runtime(Runtime.PYTHON_3_13)
            .timeout(Duration.minutes(3))
            .functionName(props.getInstanceName() + "-prefix-list-lambda")
            .build();

        prefixListFunction.addToRolePolicy(PolicyStatement.Builder.create()
            .resources(List.of("*"))
            .actions(List.of("ec2:DescribeManagedPrefixLists"))
            .build());

        var prefixListResource = CustomResource.Builder.create(this, "IdePrefixListResource")
            .serviceToken(prefixListFunction.getFunctionArn())
            .build();

        // Add managed policies
        List<IManagedPolicy> policies = new ArrayList<>();
        policies.addAll(props.getAdditionalIamPolicies());
        policies.forEach(policy -> props.getRole().addManagedPolicy(policy));

        // Create security group for IDE access
        SecurityGroup ideSecurityGroup = SecurityGroup.Builder.create(this, "IdeSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(true)
            .securityGroupName(props.getInstanceName() + "-cloudfront-ide-sg")
            .description("IDE security group")
            .build();

        ideSecurityGroup.addIngressRule(
            Peer.prefixList(prefixListResource.getAttString("PrefixListId")),
            Port.tcp(80),
            "HTTP from CloudFront only"
        );

        SecurityGroup appSecurityGroup = SecurityGroup.Builder.create(this, "AppSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(true)
            .securityGroupName(props.getInstanceName() + "-cloudfront-app-sg")
            .description("App security group")
            .build();
        if (props.getAppPort() > 0) {
            appSecurityGroup.addIngressRule(
                // Peer.prefixList(prefixListResource.getAttString("PrefixListId")),
                Peer.anyIpv4(),
                Port.tcp(props.getAppPort()),
                props.getAppPort() +  " from any"
            );
        }

        if (props.isEnableGitea()) {
            ideSecurityGroup.addIngressRule(
                Peer.ipv4(props.getVpc().getVpcCidrBlock()),
                Port.tcp(9999),
                "Gitea API from VPC"
            );
            ideSecurityGroup.addIngressRule(
                Peer.ipv4(props.getVpc().getVpcCidrBlock()),
                Port.tcp(2222),
                "Gitea SSH from VPC"
            );
        }

        var instanceProfile = InstanceProfile.Builder.create(this, "IdeInstanceProfile")
            .role(props.getRole())
            .instanceProfileName(props.getRole().getRoleName())
            .build();

        // Create Elastic IP
        CfnEIP elasticIP = CfnEIP.Builder.create(this, "IdeElasticIP")
            .domain("vpc")
            .build();

        // Create EC2 instance
        var ec2Instance = Instance.Builder.create(this, "IdeEC2Instance")
            .instanceName(props.getInstanceName())
            .vpc(props.getVpc())
            .machineImage(props.getMachineImage())
            .instanceType(props.getInstanceType())
            // .role(props.getRole())
            .instanceProfile(instanceProfile)
            .securityGroup(ideSecurityGroup)
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PUBLIC)
                .build())
            .blockDevices(List.of(BlockDevice.builder()
                .deviceName("/dev/xvda")
                .volume(BlockDeviceVolume.ebs(props.getDiskSize(), EbsDeviceOptions.builder()
                    .volumeType(EbsDeviceVolumeType.GP3)
                    .deleteOnTermination(true)
                    .encrypted(true)
                    .build()))
                .build()))
            .build();

        // Associate Elastic IP with the instance
        var ipAssociation = CfnEIPAssociation.Builder.create(this, "IdeEipAssociation")
            .allocationId(elasticIP.getAttrAllocationId())
            .instanceId(ec2Instance.getInstanceId())
            .build();

        // Internal security group, allow traffic only between members
        ideInternalSecurityGroup = SecurityGroup.Builder.create(this, "IdeInternalSecurityGroup")
            .vpc(props.getVpc())
            .allowAllOutbound(false)
            .securityGroupName(props.getInstanceName() + "-internal-sg")
            .description("IDE internal security group")
            .build();
        // Add ingress rule to allow all traffic from within the same security group
        ideInternalSecurityGroup.getConnections().allowInternally(
            Port.allTraffic(),
            "Allow all internal traffic"
        );
        ec2Instance.addSecurityGroup(ideInternalSecurityGroup);
        if (props.getAppPort() > 0) {
            ec2Instance.addSecurityGroup(appSecurityGroup);
        }
        // Add additional security groups if any
        props.getAdditionalSecurityGroups().forEach(sg -> ec2Instance.addSecurityGroup(sg));

        // Set up wait condition
        var waitHandle = CfnWaitConditionHandle.Builder.create(this, "IdeBootstrapWaitConditionHandle")
            .build();

        var waitCondition = CfnWaitCondition.Builder.create(this, "IdeBootstrapWaitCondition")
            .count(1)
            .handle(waitHandle.getRef())
            .timeout(String.valueOf(props.getBootstrapTimeoutMinutes() * 60))
            .build();
        waitCondition.getNode().addDependency(ec2Instance);

        // Create CloudFront distribution
        var distribution = Distribution.Builder.create(this, "IdeDistribution")
            .defaultBehavior(BehaviorOptions.builder()
                .origin(new HttpOrigin(ec2Instance.getInstancePublicDnsName(),
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
        // if (props.getAppPort() > 0) {
        //     distribution.addBehavior(
        //         "/app/*",
        //         new HttpOrigin(ec2Instance.getInstancePublicDnsName(),
        //             HttpOriginProps.builder()
        //                 .protocolPolicy(OriginProtocolPolicy.HTTP_ONLY)
        //                 .httpPort(props.getAppPort())
        //                 .build()),
        //         AddBehaviorOptions.builder()
        //             .allowedMethods(AllowedMethods.ALLOW_ALL)
        //             .cachePolicy(CachePolicy.CACHING_DISABLED)
        //             .originRequestPolicy(OriginRequestPolicy.ALL_VIEWER)
        //             .viewerProtocolPolicy(ViewerProtocolPolicy.ALLOW_ALL)
        //             .build()
        //     );
        // }
        distribution.applyRemovalPolicy(RemovalPolicy.DESTROY);
        distribution.getNode().addDependency(ipAssociation);

        var outputIdeUrl = CfnOutput.Builder.create(this, "IdeUrl")
            .value("https://" + distribution.getDistributionDomainName())
            .description("Workshop IDE Url")
            .exportName(props.getInstanceName() + "-url")
            .build();
        outputIdeUrl.overrideLogicalId("IdeUrl");

        // Create password secret
        ideSecretsManagerPassword = Secret.Builder.create(this, "IdePasswordSecret")
            .generateSecretString(SecretStringGenerator.builder()
                .excludePunctuation(true)
                .passwordLength(32)
                .generateStringKey("password")
                .includeSpace(false)
                .secretStringTemplate("{\"password\":\"\"}")
                .excludeCharacters("\"@/\\\\")
                .build())
            .secretName(props.getInstanceName() + "-password-lambda")
            .build();
        ec2Instance.getNode().addDependency(ideSecretsManagerPassword);

        ideSecretsManagerPassword.grantRead(props.getRole());
        var outputIdePassword = CfnOutput.Builder.create(this, "IdePassword")
            .value(getIdePassword(props.getInstanceName()))
            .description("Workshop IDE Password")
            .exportName(props.getInstanceName() + "-password")
            .build();
        outputIdePassword.getNode().addDependency(ideSecretsManagerPassword);
        outputIdePassword.overrideLogicalId("IdePassword");

        // Create SSM document
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("BootstrapScript", Map.of(
            "type", "String",
            "description", "(Optional) Custom bootstrap script to run.",
            "default", ""
        ));

        Map<String, Object> inputs = new HashMap<>();
        inputs.put("runCommand", Arrays.asList(
            Fn.sub(loadFile("/bootstrapDocument.sh"), Map.ofEntries(
                Map.entry("instanceIamRoleName", props.getRole().getRoleName()),
                Map.entry("instanceIamRoleArn", props.getRole().getRoleArn()),
                Map.entry("passwordName", ideSecretsManagerPassword.getSecretName()),
                Map.entry("domain", ""),
                // Map.entry("domain", distribution.getDistributionDomainName()),
                Map.entry("codeServerVersion", props.getCodeServerVersion()),
                Map.entry("waitConditionHandleUrl", waitHandle.getRef()),
                Map.entry("customBootstrapScript", props.getBootstrapScript()),
                Map.entry("installGitea", addGiteaToSSMTemplate(props.isEnableGitea())),
                Map.entry("splashUrl", props.getSplashUrl()),
                Map.entry("readmeUrl", props.getReadmeUrl()),
                Map.entry("environmentContentsZip", props.getEnvironmentContentsZip()),
                Map.entry("extensions", String.join(",", props.getExtensions())),
                Map.entry("terminalOnStartup", String.valueOf(props.isTerminalOnStartup()))
            ))
        ));

        Map<String, Object> mainStep = new HashMap<>();
        mainStep.put("action", "aws:runShellScript");
        mainStep.put("name", "IdeBootstrapFunction");
        mainStep.put("inputs", inputs);

        Map<String, Object> content = new HashMap<>();
        content.put("schemaVersion", "2.2");
        content.put("description", "Bootstrap IDE");
        content.put("parameters", parameters);
        content.put("mainSteps", Arrays.asList(mainStep));

        var ssmDocument = CfnDocument.Builder.create(this, "IdeBootstrapDocument")
            .documentType("Command")
            .documentFormat("YAML")
            .updateMethod("NewVersion")
            .name(props.getInstanceName() + "-bootstrap-document")
            .content(content)
            .build();
        waitCondition.getNode().addDependency(ssmDocument);

        // Create bootstrap function
        Function bootstrapFunction = Function.Builder.create(this, "IdeBootstrapFunction")
            .code(Code.fromInline(loadFile("/lambda.py")))
            .handler("index.lambda_handler")
            .runtime(Runtime.PYTHON_3_13)
            .timeout(Duration.minutes(15))
            .functionName(props.getInstanceName() + "-bootstrap-lambda")
            .build();

        bootstrapFunction.addToRolePolicy(PolicyStatement.Builder.create()
            .resources(List.of(props.getRole().getRoleArn()))
            .actions(List.of("iam:PassRole"))
            .build());

        bootstrapFunction.addToRolePolicy(PolicyStatement.Builder.create()
            .resources(List.of("*"))
            .actions(List.of(
                "ec2:DescribeInstances",
                "iam:ListInstanceProfiles",
                "ssm:DescribeInstanceInformation",
                "ssm:SendCommand",
                "ssm:GetCommandInvocation"
            ))
            .build());

        // Create bootstrap resource
        CustomResource.Builder.create(this, "IdeBootstrapResource")
            .serviceToken(bootstrapFunction.getFunctionArn())
            .properties(Map.of(
                "InstanceId", ec2Instance.getInstanceId(),
                "SsmDocument", ssmDocument.getRef(),
                "LogGroupName", logGroup.getLogGroupName()
            ))
            .build();
    }

    public SecurityGroup getIdeInternalSecurityGroup() {
        return ideInternalSecurityGroup;
    }

    private String getIdePassword(final String prefix) {
        if (passwordResource == null) {
            Function passwordFunction = Function.Builder.create(this, "IdePasswordExporterFunction")
                .code(Code.fromInline(loadFile("/password.py")))
                .handler("index.lambda_handler")
                .runtime(Runtime.PYTHON_3_13)
                .timeout(Duration.minutes(3))
                .functionName(prefix + "-password-lambda")
                .build();

            ideSecretsManagerPassword.grantRead(passwordFunction);

            passwordResource = CustomResource.Builder.create(this, "IdePasswordExporter")
                .serviceToken(passwordFunction.getFunctionArn())
                .properties(Map.of(
                    "PasswordName", this.ideSecretsManagerPassword.getSecretName()
                ))
                .build();
        }

        return passwordResource.getAttString("password");
    }

    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    private String addGiteaToSSMTemplate(Boolean enableGitea) {
        if (!enableGitea) {
            return "echo bootstrapGitea was not provided";
        }
        else {
            return loadFile("/bootstrapGitea.sh");
        }
    }
}
