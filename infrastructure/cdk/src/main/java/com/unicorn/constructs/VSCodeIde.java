package com.unicorn.constructs;

import software.amazon.awscdk.CfnWaitCondition;
import software.amazon.awscdk.CfnWaitConditionHandle;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.cloudfront.AddBehaviorOptions;
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
import software.amazon.awscdk.services.ec2.EbsDeviceOptions;
import software.amazon.awscdk.services.ec2.EbsDeviceVolumeType;
import software.amazon.awscdk.services.ec2.Instance;
import software.amazon.awscdk.services.ec2.Peer;
import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.iam.IManagedPolicy;
import software.amazon.awscdk.services.iam.InstanceProfile;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyDocument;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.secretsmanager.Secret;
import software.amazon.awscdk.services.secretsmanager.SecretStringGenerator;
import software.amazon.awscdk.services.ssm.CfnDocument;
import software.amazon.awscdk.CfnOutput;

import software.constructs.Construct;
import org.json.JSONObject;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class VSCodeIde extends Construct {

    private CustomResource passwordResource;
    private Secret ideSecretsManagerPassword;

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
            throw new IllegalArgumentException("IdeRole must be provided in the properties and cannot be null");
        }

        // props.getRole().addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess"));
        props.getRole().addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("ReadOnlyAccess"));
        props.getRole().addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"));

        var filePath = props.getAdditionalIamPolicyPath();
        if (Files.exists(Path.of(getClass().getResource(filePath).getPath()))) {
            var policyDocumentJson = loadFile(filePath);
            var policyDocument = PolicyDocument.fromJson(new JSONObject(policyDocumentJson).toMap());
            var policy = ManagedPolicy.Builder.create(this, "WorkshopIdeUserPolicy")
                .document(policyDocument)
                .build();
                props.getRole().addManagedPolicy(policy);
        }

        // Set up logging
        LogGroup logGroup = LogGroup.Builder.create(this, "IdeLogGroup")
            .retention(RetentionDays.ONE_WEEK)
            .logGroupName("unicornstore-ide-bootstrap")
            .build();
        logGroup.grantWrite(props.getRole());

        // Create prefix List of CloudFront IP for EC2 instance segurity Group
        Function prefixListFunction = Function.Builder.create(this, "IdePrefixListFunction")
            .code(Code.fromInline(loadFile("/prefix-lambda.py")))
            .handler("index.lambda_handler")
            .runtime(Runtime.PYTHON_3_13)
            .timeout(Duration.minutes(3))
            .functionName("unicornstore-vscode-ide-prefix-list-lambda")
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
            .securityGroupName("unicornstore-cloudfront-ide-sg")
            .description("IDE security group")
            .build();

        ideSecurityGroup.addIngressRule(
            Peer.prefixList(prefixListResource.getAttString("PrefixListId")),
            Port.tcp(80),
            "HTTP from CloudFront only"
        );

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

        if (props.isEnableAppSecurityGroup()) {
            // Create security group
            SecurityGroup appSecurityGroup = SecurityGroup.Builder.create(this, "AppSecurityGroup")
                .vpc(props.getVpc())
                .allowAllOutbound(true)
                .securityGroupName("unicornstore-cloudfront-app-sg")
                .description("App security group")
                .build();

            appSecurityGroup.addIngressRule(
                Peer.prefixList(prefixListResource.getAttString("PrefixListId")),
                Port.tcp(props.getAppPort()),
                "Port " + props.getAppPort() +  " to App from CloudFront only"
            );
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
        if (props.isEnableAppSecurityGroup()) {
            distribution.addBehavior(
                "/app/*",
                new HttpOrigin(ec2Instance.getInstancePublicDnsName(),
                    HttpOriginProps.builder()
                        .protocolPolicy(OriginProtocolPolicy.HTTP_ONLY)
                        .httpPort(props.getAppPort())
                        .build()),
                AddBehaviorOptions.builder()
                    .allowedMethods(AllowedMethods.ALLOW_ALL)
                    .cachePolicy(CachePolicy.CACHING_DISABLED)
                    .originRequestPolicy(OriginRequestPolicy.ALL_VIEWER)
                    .viewerProtocolPolicy(ViewerProtocolPolicy.ALLOW_ALL)
                    .build()
            );
        }
        distribution.applyRemovalPolicy(RemovalPolicy.DESTROY);

        var outputIdeUrl = CfnOutput.Builder.create(this, "IdeUrl")
            .value("https://" + distribution.getDistributionDomainName())
            .description("Workshop IDE Url")
            .exportName("IdeUrl")
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
            .secretName("unicornstore-vscode-ide-password-lambda")
            .build();
        ec2Instance.getNode().addDependency(ideSecretsManagerPassword);

        ideSecretsManagerPassword.grantRead(props.getRole());
        var outputIdePassword = CfnOutput.Builder.create(this, "IdePassword")
            .value(getIdePassword())
            .description("Workshop IDE Password")
            .exportName("IdePassword")
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
            .content(content)
            .build();
        waitCondition.getNode().addDependency(ssmDocument);

        // Create bootstrap function
        Function bootstrapFunction = Function.Builder.create(this, "IdeBootstrapFunction")
            .code(Code.fromInline(loadFile("/lambda.py")))
            .handler("index.lambda_handler")
            .runtime(Runtime.PYTHON_3_13)
            .timeout(Duration.minutes(15))
            .functionName("unicornstore-vscode-ide-bootstrap-lambda")
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

    private String getIdePassword() {
        if (passwordResource == null) {
            Function passwordFunction = Function.Builder.create(this, "IdePasswordExporterFunction")
                .code(Code.fromInline(loadFile("/password.py")))
                .handler("index.lambda_handler")
                .runtime(Runtime.PYTHON_3_13)
                .timeout(Duration.minutes(3))
                .functionName("unicornstore-vscode-ide-password-lambda")
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
