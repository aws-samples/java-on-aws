package com.unicorn.constructs;

import com.unicorn.core.InfrastructureStack;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnOutputProps;
import software.amazon.awscdk.services.ecr.IRepository;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.ecs.AwsLogDriver;
import software.amazon.awscdk.services.ecs.Cluster;
import software.amazon.awscdk.services.ecs.ContainerImage;
import software.amazon.awscdk.services.ecs.CpuArchitecture;
import software.amazon.awscdk.services.ecs.DeploymentCircuitBreaker;
import software.amazon.awscdk.services.ecs.OperatingSystemFamily;
import software.amazon.awscdk.services.ecs.RuntimePlatform;
// import software.amazon.awscdk.services.ecs.ContainerDefinition;
// import software.amazon.awscdk.services.ecs.ContainerDefinitionOptions;
// import software.amazon.awscdk.services.ecs.ContainerDependency;
// import software.amazon.awscdk.services.ecs.ContainerDependencyCondition;
import software.amazon.awscdk.services.ecs.patterns.ApplicationLoadBalancedFargateService;
import software.amazon.awscdk.services.ecs.patterns.ApplicationLoadBalancedTaskImageOptions;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.codebuild.PipelineProject;
import software.amazon.awscdk.services.codebuild.BuildSpec;
import software.amazon.awscdk.services.codebuild.ComputeType;
import software.amazon.awscdk.services.codebuild.LinuxBuildImage;
import software.amazon.awscdk.services.codebuild.BuildEnvironment;
import software.amazon.awscdk.services.codebuild.BuildEnvironmentVariable;
import software.amazon.awscdk.services.codepipeline.Pipeline;
import software.amazon.awscdk.services.codepipeline.Artifact;
import software.amazon.awscdk.services.codepipeline.StageProps;
import software.amazon.awscdk.services.codepipeline.actions.CodeBuildAction;
import software.amazon.awscdk.services.codepipeline.actions.EcrSourceAction;
import software.amazon.awscdk.services.codepipeline.actions.EcsDeployAction;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;

import software.amazon.awscdk.Duration;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class UnicornStoreECS extends Construct {

    public UnicornStoreECS(final Construct scope, final String id,
            InfrastructureStack infrastructureStack, final String projectName) {
        super(scope, id);

        Cluster cluster =
                Cluster.Builder.create(scope, projectName + "-cluster").clusterName(projectName)
                        .vpc(infrastructureStack.getVpc()).containerInsights(true).build();

        Role taskRole = Role.Builder.create(scope, projectName + "-task-role")
                .assumedBy(new ServicePrincipal("ecs-tasks.amazonaws.com")).build();

        Role executionRole = Role.Builder.create(scope, projectName + "-execution-role")
                .assumedBy(new ServicePrincipal("ecs-tasks.amazonaws.com")).build();

        LogGroup logGroup = LogGroup.Builder.create(scope, projectName + "-log-group")
                .logGroupName("/aws/ecs/" + projectName).removalPolicy(RemovalPolicy.DESTROY)
                .build();

        AwsLogDriver logging =
                AwsLogDriver.Builder.create().logGroup(logGroup).streamPrefix("ecs").build();

        ApplicationLoadBalancedFargateService loadBalancedFargateService =
                ApplicationLoadBalancedFargateService.Builder.create(scope, projectName + "-ecs")
                        .cluster(cluster).serviceName(projectName).memoryLimitMiB(2048).cpu(1024)
                        .runtimePlatform(
                                RuntimePlatform.builder()
                                        // .cpuArchitecture(CpuArchitecture.ARM64)
                                        .cpuArchitecture(CpuArchitecture.X86_64)
                                        .operatingSystemFamily(OperatingSystemFamily.LINUX).build())
                        .desiredCount(1)
                        .taskImageOptions(ApplicationLoadBalancedTaskImageOptions.builder()
                                .family(projectName).containerName(projectName)
                                .executionRole(executionRole).taskRole(taskRole).logDriver(logging)
                                .image(ContainerImage.fromRegistry(infrastructureStack.getAccount()
                                        + ".dkr.ecr." + infrastructureStack.getRegion()
                                        + ".amazonaws.com/" + projectName + ":latest"))
                                .containerPort(8080)
                                .enableLogging(true)
                                .environment(Map.of("SPRING_DATASOURCE_PASSWORD",
                                        infrastructureStack.getDatabaseSecretString(),
                                        "SPRING_DATASOURCE_URL",
                                        infrastructureStack.getDatabaseJDBCConnectionString()))
                                .build())
                        .circuitBreaker(DeploymentCircuitBreaker.builder().rollback(true).build())
                        .loadBalancerName(projectName).publicLoadBalancer(true).build();

        new CfnOutput(scope, "UnicornStoreServiceURL",
                CfnOutputProps.builder().value("http://"
                        + loadBalancedFargateService.getLoadBalancer().getLoadBalancerDnsName())
                        .build());

        infrastructureStack.getEventBridge()
                .grantPutEventsTo(loadBalancedFargateService.getTaskDefinition().getTaskRole());
        infrastructureStack.getSecretPassword().grantRead(loadBalancedFargateService.getTaskDefinition().getTaskRole());
        infrastructureStack.getParamJdbsc().grantRead(loadBalancedFargateService.getTaskDefinition().getTaskRole());

        // https://raw.githubusercontent.com/aws-observability/aws-otel-collector/main/deployment-template/ecs/aws-otel-fargate-sidecar-deployment-cfn.yaml
        PolicyStatement executionRolePolicy = PolicyStatement.Builder.create().effect(Effect.ALLOW)
                .actions(List.of("ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
                        "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
                        "cloudwatch:PutMetricData"))
                .resources(List.of("*")).build();

        PolicyStatement AWSOpenTelemetryPolicy = PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream",
                        "logs:DescribeLogStreams", "logs:DescribeLogGroups",
                        "logs:PutRetentionPolicy", "xray:PutTraceSegments",
                        "xray:PutTelemetryRecords", "xray:GetSamplingRules",
                        "xray:GetSamplingTargets", "xray:GetSamplingStatisticSummaries",
                        "cloudwatch:PutMetricData", "ssm:GetParameters"))
                .resources(List.of("*")).build();

        loadBalancedFargateService.getTaskDefinition()
                .addToExecutionRolePolicy(executionRolePolicy);
        loadBalancedFargateService.getTaskDefinition().addToTaskRolePolicy(AWSOpenTelemetryPolicy);

        loadBalancedFargateService.getTaskDefinition().getExecutionRole()
                .addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(scope,
                        projectName + "AmazonECSTaskExecutionRolePolicy",
                        "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"));
        loadBalancedFargateService.getTaskDefinition().getExecutionRole()
                .addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(scope,
                        projectName + "AWSXrayWriteOnlyAccess",
                        "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"));
        loadBalancedFargateService.getTaskDefinition().getExecutionRole()
                .addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(scope,
                        projectName + "CloudWatchLogsFullAccess",
                        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"));
        loadBalancedFargateService.getTaskDefinition().getExecutionRole()
                .addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(scope,
                        projectName + "AmazonSSMReadOnlyAccess",
                        "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"));

        // // https://docs.aws.amazon.com/xray/latest/devguide/xray-java-opentel-sdk.html
        // loadBalancedFargateService.getTaskDefinition().addContainer("otel-collector",
        //         ContainerDefinitionOptions.builder()
        //                 .image(ContainerImage.fromRegistry("amazon/aws-otel-collector:latest"))
        //                 // --config=/etc/ecs/ecs-amp-xray.yaml
        //                 // --config=/etc/ecs/ecs-default-config.yaml
        //                 .command(List.of("--config", "/etc/ecs/ecs-xray.yaml")).logging(logging)
        //                 .build());

        // ContainerDefinition otel =
        //         loadBalancedFargateService.getTaskDefinition().findContainer("otel-collector");

        // ContainerDependency dependsOnOtel = ContainerDependency.builder().container(otel)
        //         .condition(ContainerDependencyCondition.START).build();
        // loadBalancedFargateService.getTaskDefinition().findContainer(projectName)
        //         .addContainerDependencies(dependsOnOtel);

        // deployment construct which listens to ECR events, then deploys to the
        // existing service.
        IRepository ecr = Repository.fromRepositoryName(scope, projectName + "-ecr", projectName);
        ecr.grantPull(loadBalancedFargateService.getTaskDefinition().getExecutionRole());

        Artifact sourceOuput = Artifact.artifact(projectName + "-ecr-artifact");
        Artifact buildOuput = Artifact.artifact(projectName + "-ecs-artifact");

        EcrSourceAction sourceAction = EcrSourceAction.Builder.create().actionName("source-ecr")
                .repository(ecr).imageTag("latest").output(sourceOuput)
                .variablesNamespace("ecrvars").build();

        EcsDeployAction deployAction = EcsDeployAction.Builder.create().actionName("deploy-ecs")
                .input(buildOuput).service(loadBalancedFargateService.getService()).build();

        PipelineProject codeBuild =
                PipelineProject.Builder.create(scope, projectName + "-codebuild-deploy-ecs")
                        .projectName(projectName + "-deploy-ecs").vpc(infrastructureStack.getVpc())
                        .environment(BuildEnvironment
                                .builder().privileged(true).computeType(ComputeType.SMALL)
                                .buildImage(LinuxBuildImage.AMAZON_LINUX_2_4).build())
                        .buildSpec(BuildSpec.fromObject(Map.of("version", "0.2", "phases",
                                Map.of("build", Map.of("commands", List.of("cat imageDetail.json",
                                        "IMAGE_DETAIL_URI=$(cat imageDetail.json | python -c \"import sys, json; print(json.load(sys.stdin)['ImageURI'].split('@')[0])\")",
                                        "IMAGE_DETAIL_TAG=$(cat imageDetail.json | python -c \"import sys, json; a=json.load(sys.stdin)['ImageTags']; a.sort(); print(a[0])\")",
                                        "echo $IMAGE_DETAIL_URI:$IMAGE_DETAIL_TAG",
                                        "echo IMAGE_URI=$IMAGE_URI", "echo IMAGE_TAG=$IMAGE_TAG",
                                        "echo $(jq -n --arg iu \"$IMAGE_DETAIL_URI:$IMAGE_DETAIL_TAG\" --arg app \""
                                                + projectName
                                                + "\" '[{name:$app,imageUri:$iu}]\') > imagedefinitions.json",
                                        "cat imagedefinitions.json"))),
                                "artifacts", Map.of("files", List.of("imagedefinitions.json")))))
                        .environmentVariables(Map.of("IMAGE_URI",
                                BuildEnvironmentVariable.builder()
                                        .value(sourceAction.getVariables().getImageUri()).build(),
                                "IMAGE_TAG",
                                BuildEnvironmentVariable.builder()
                                        .value(sourceAction.getVariables().getImageTag()).build()))
                        .timeout(Duration.minutes(60)).build();

        Pipeline.Builder.create(scope, projectName + "-pipeline-deploy-ecs")
                .pipelineName(projectName + "-deploy-ecs").crossAccountKeys(false)
                .stages(List.of(
                        StageProps.builder().stageName("source").actions(List.of(sourceAction))
                                .build(),
                        StageProps.builder().stageName("build")
                                .actions(List.of(CodeBuildAction.Builder.create()
                                        .actionName("build-imagedefinitions").input(sourceOuput)
                                        .project(codeBuild).outputs(List.of(buildOuput)).runOrder(1)
                                        .build()))
                                .build(),
                        StageProps.builder().stageName("deploy").actions(List.of(deployAction))
                                .build()))
                .build();
    }
}
