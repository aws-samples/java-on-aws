package com.unicorn.core;

import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.ec2.Peer;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.ec2.ISecurityGroup;
import software.amazon.awscdk.RemovalPolicy;
import software.constructs.Construct;

import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.ecs.Cluster;
import software.amazon.awscdk.services.ecs.ContainerImage;
import software.amazon.awscdk.services.ecs.FargateTaskDefinition;
import software.amazon.awscdk.services.ecs.FargateService;
import software.amazon.awscdk.services.ecs.AwsLogDriverProps;
import software.amazon.awscdk.services.ecs.LogDriver;
import software.amazon.awscdk.services.ecs.Protocol;
import software.amazon.awscdk.services.ecs.PortMapping;
import software.amazon.awscdk.services.elasticloadbalancingv2.ApplicationLoadBalancer;
import software.amazon.awscdk.services.elasticloadbalancingv2.ApplicationListener;
import software.amazon.awscdk.services.elasticloadbalancingv2.ApplicationProtocol;
import software.amazon.awscdk.services.elasticloadbalancingv2.ApplicationTargetGroup;
import software.amazon.awscdk.services.elasticloadbalancingv2.TargetType;
import software.amazon.awscdk.services.ecs.LoadBalancerTargetOptions;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.Duration;

import java.util.List;
import java.util.Map;

public class InfrastructureEcs extends Construct {

    private final String appName;
    private final Repository ecrRepository;
    private final Cluster ecsCluster;
    private final ApplicationLoadBalancer loadBalancer;
    private final FargateService fargateService;

    private final InfrastructureCore infrastructureCore;

    public InfrastructureEcs(final Construct scope, final String id, final InfrastructureCore infrastructureCore, final String appName) {
        super(scope, id);

        this.appName = appName;
        this.infrastructureCore = infrastructureCore;

        // Create ECR Repository
        ecrRepository = createEcrRepository();

        // Create ECS Cluster
        ecsCluster = createEcsCluster();

        // Create Security Groups
        ISecurityGroup albSecurityGroup = createAlbSecurityGroup();
        ISecurityGroup ecsSecurityGroup = createEcsSecurityGroup(albSecurityGroup);

        // Create ALB
        loadBalancer = createLoadBalancer(albSecurityGroup);

        // Create ECS Service with Fargate
        fargateService = createFargateService(ecsSecurityGroup, loadBalancer);
    }

    private Repository createEcrRepository() {
        return Repository.Builder.create(this, appName + "-EcrRepository")
            .repositoryName(appName)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();
    }

    private Cluster createEcsCluster() {
        return Cluster.Builder.create(this, appName + "-EcsCluster")
            .clusterName(appName)
            .vpc(infrastructureCore.getVpc())
            .build();
    }

    private ISecurityGroup createAlbSecurityGroup() {
        SecurityGroup sg = SecurityGroup.Builder.create(this, appName + "-AlbSecurityGroup")
            .vpc(infrastructureCore.getVpc())
            .securityGroupName(appName + "-ecs-sg-alb")
            .description("Security group for " + appName + " ALB")
            .build();

        sg.addIngressRule(Peer.anyIpv4(), Port.tcp(80), "Allow HTTP traffic from anywhere");

        return sg;
    }

    private ISecurityGroup createEcsSecurityGroup(ISecurityGroup albSecurityGroup) {
        SecurityGroup sg = SecurityGroup.Builder.create(this, appName + "-EcsSecurityGroup")
            .vpc(infrastructureCore.getVpc())
            .securityGroupName(appName + "-ecs-sg")
            .description("Security group for " + appName + " ECS Service")
            .build();

        sg.addIngressRule(albSecurityGroup, Port.tcp(8080), "Allow traffic from ALB on port 8080");

        return sg;
    }

    private ApplicationLoadBalancer createLoadBalancer(ISecurityGroup albSecurityGroup) {
        return ApplicationLoadBalancer.Builder.create(this, appName + "-Alb")
            .loadBalancerName(appName)
            .vpc(infrastructureCore.getVpc())
            .internetFacing(true)
            .securityGroup(albSecurityGroup)
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PUBLIC)
                .build())
            .build();
    }

    private FargateService createFargateService(ISecurityGroup ecsSecurityGroup, ApplicationLoadBalancer alb) {
        // Create Task Definition
        FargateTaskDefinition taskDefinition = FargateTaskDefinition.Builder.create(this, appName + "-TaskDef")
            .family(appName)
            .cpu(1024)
            .memoryLimitMiB(2048)
            .build();

        // Add container to task definition using a public nginx image
        var containerDefinitionProps = software.amazon.awscdk.services.ecs.ContainerDefinitionOptions.builder()
            .image(ContainerImage.fromRegistry("nginxinc/nginx-unprivileged:stable"))
            .containerName(appName)
            .essential(true)
            .environment(Map.of(
                "NGINX_PORT", "8080"
            ))
            .portMappings(List.of(PortMapping.builder()
                .containerPort(8080)
                .hostPort(8080)
                .protocol(Protocol.TCP)
                .build()))
            .logging(LogDriver.awsLogs(AwsLogDriverProps.builder()
                .logGroup(LogGroup.Builder.create(this, appName + "-LogGroup")
                    .logGroupName("/ecs/" + appName)
                    .removalPolicy(RemovalPolicy.DESTROY)
                    .build())
                .streamPrefix("ecs")
                .build()))
            .secrets(Map.of(
                "SPRING_DATASOURCE_URL", software.amazon.awscdk.services.ecs.Secret.fromSsmParameter(infrastructureCore.getParamDBConnectionString()),
                "SPRING_DATASOURCE_PASSWORD", software.amazon.awscdk.services.ecs.Secret.fromSecretsManager(infrastructureCore.getDatabaseSecret())
            ))
            .build();
        taskDefinition.addContainer(appName + "-Container", containerDefinitionProps);

        // Create target group for the ALB
        var healthCheckOptions = software.amazon.awscdk.services.elasticloadbalancingv2.HealthCheck.builder()
            .path("/")
            .timeout(Duration.seconds(5))
            .interval(Duration.seconds(30))
            .healthyHttpCodes("200")
            .build();

        ApplicationTargetGroup targetGroup = ApplicationTargetGroup.Builder.create(this, appName + "-TargetGroup")
            .targetGroupName(appName)
            .vpc(infrastructureCore.getVpc())
            .port(8080)
            .protocol(ApplicationProtocol.HTTP)
            .targetType(TargetType.IP)
            .healthCheck(healthCheckOptions)
            .build();

        // Create listener
        ApplicationListener.Builder.create(this, appName + "-Listener")
            .loadBalancer(alb)
            .port(80)
            .defaultTargetGroups(List.of(targetGroup))
            .build();

        // Create Fargate Service with target group attachment
        var service = FargateService.Builder.create(this, appName + "-Service")
            .serviceName(appName)
            .cluster(ecsCluster)
            .taskDefinition(taskDefinition)
            .desiredCount(1)
            .securityGroups(List.of(ecsSecurityGroup))
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .assignPublicIp(false)
            .build();

        // Register the service with the target group
        targetGroup.addTarget(service.loadBalancerTarget(LoadBalancerTargetOptions.builder()
            .containerName(appName)
            .containerPort(8080)
            .build()));
        return service;
    }

    public Repository getEcrRepository() {
        return ecrRepository;
    }

    public Cluster getEcsCluster() {
        return ecsCluster;
    }

    public ApplicationLoadBalancer getLoadBalancer() {
        return loadBalancer;
    }

    public FargateService getFargateService() {
        return fargateService;
    }
}
