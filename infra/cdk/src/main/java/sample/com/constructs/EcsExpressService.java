package sample.com.constructs;

import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.ecs.CfnExpressGatewayService;
import software.amazon.awscdk.services.ecs.Cluster;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.logs.LogGroup;
import software.constructs.Construct;
import software.constructs.IDependable;

import java.util.List;
import java.util.function.Consumer;

/**
 * Self-contained ECS Express Mode service construct.
 * Creates ECS cluster, IAM roles, and ECS Express Gateway Service with ALB.
 * ECR repos are created via create-on-push.
 *
 * All resources use appName as prefix for consistent naming.
 *
 * Task role has base permissions (CloudWatch, X-Ray) and can be customized
 * via configureTaskRole callback for app-specific permissions (Bedrock, EventBridge, etc.)
 */
public class EcsExpressService extends Construct {

    private final Cluster ecsCluster;
    private final CfnExpressGatewayService expressService;
    private final Role infrastructureRole;
    private final Role taskExecutionRole;
    private final Role taskRole;

    public EcsExpressService(final Construct scope, final String id, final EcsExpressServiceProps props) {
        super(scope, id);

        String appName = props.getAppName();
        ServicePrincipal ecsService = ServicePrincipal.Builder.create("ecs.amazonaws.com").build();
        ServicePrincipal ecsTasks = ServicePrincipal.Builder.create("ecs-tasks.amazonaws.com").build();

        // === Infrastructure Role (for Express Mode) ===
        this.infrastructureRole = Role.Builder.create(this, "InfrastructureRole")
            .roleName(appName + "-ecs-infrastructure-role")
            .path("/service-role/")
            .assumedBy(ecsService)
            .description("ECS infrastructure role for Express Mode")
            .build();
        infrastructureRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName(
            "service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"));

        // === Task Execution Role ===
        this.taskExecutionRole = Role.Builder.create(this, "TaskExecutionRole")
            .roleName(appName + "-ecs-task-execution-role")
            .path("/service-role/")
            .assumedBy(ecsTasks)
            .description("ECS task execution role for pulling images and injecting secrets")
            .build();
        taskExecutionRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName(
            "service-role/AmazonECSTaskExecutionRolePolicy"));
        taskExecutionRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("logs:CreateLogGroup"))
            .resources(List.of("*"))
            .build());
        props.getDatabase().grantSecretsRead(taskExecutionRole);

        // === Task Role (app runtime permissions) ===
        this.taskRole = Role.Builder.create(this, "TaskRole")
            .roleName(appName + "-ecs-task-role")
            .path("/service-role/")
            .assumedBy(ecsTasks)
            .description("ECS task role for application runtime permissions")
            .build();
        taskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy"));
        taskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AWSXrayWriteOnlyAccess"));
        if (props.getConfigureTaskRole() != null) {
            props.getConfigureTaskRole().accept(taskRole);
        }

        // Build ECR image URI (repos created via create-on-push)
        String imageUri = Fn.sub("${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/" + appName + ":latest");

        // Create ECS Cluster
        this.ecsCluster = Cluster.Builder.create(this, "EcsCluster")
            .clusterName(appName)
            .vpc(props.getVpc())
            .build();

        // Create CloudWatch Log Group
        LogGroup logGroup = LogGroup.Builder.create(this, "LogGroup")
            .logGroupName("/aws/ecs/" + appName)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Get PUBLIC subnets for the service (Express Mode uses public subnets with ALB)
        List<String> publicSubnetIds = props.getVpc().selectSubnets(SubnetSelection.builder()
            .subnetType(SubnetType.PUBLIC)
            .build()).getSubnetIds();

        // Get DB security group ID for network access
        String dbSecurityGroupId = props.getDatabase().getDatabaseSecurityGroup().getSecurityGroupId();

        // Create ECS Express Gateway Service
        this.expressService = CfnExpressGatewayService.Builder.create(this, "ExpressService")
            .serviceName(appName)
            .cluster(ecsCluster.getClusterName())
            .infrastructureRoleArn(infrastructureRole.getRoleArn())
            .executionRoleArn(taskExecutionRole.getRoleArn())
            .taskRoleArn(taskRole.getRoleArn())
            .primaryContainer(CfnExpressGatewayService.ExpressGatewayContainerProperty.builder()
                .image(imageUri)
                .containerPort(8080)
                .awsLogsConfiguration(CfnExpressGatewayService.ExpressGatewayServiceAwsLogsConfigurationProperty.builder()
                    .logGroup(logGroup.getLogGroupName())
                    .logStreamPrefix("ecs")
                    .build())
                .secrets(List.of(
                    CfnExpressGatewayService.SecretProperty.builder()
                        .name("SPRING_DATASOURCE_URL")
                        .valueFrom(props.getDatabase().getParamDBConnectionString().getParameterArn())
                        .build(),
                    CfnExpressGatewayService.SecretProperty.builder()
                        .name("SPRING_DATASOURCE_USERNAME")
                        .valueFrom(props.getDatabase().getDatabaseSecret().getSecretArn() + ":username::")
                        .build(),
                    CfnExpressGatewayService.SecretProperty.builder()
                        .name("SPRING_DATASOURCE_PASSWORD")
                        .valueFrom(props.getDatabase().getDatabaseSecret().getSecretArn() + ":password::")
                        .build()
                ))
                .build())
            .cpu("1024")
            .memory("2048")
            .healthCheckPath("/")
            .networkConfiguration(CfnExpressGatewayService.ExpressGatewayServiceNetworkConfigurationProperty.builder()
                .subnets(publicSubnetIds)
                .securityGroups(List.of(dbSecurityGroupId))
                .build())
            .scalingTarget(CfnExpressGatewayService.ExpressGatewayScalingTargetProperty.builder()
                .minTaskCount(1)
                .maxTaskCount(4)
                .autoScalingMetric("AVERAGE_CPU")
                .autoScalingTargetValue(70)
                .build())
            .build();

        // Add dependency on CodeBuild (image must be pushed before service starts)
        if (props.getDependsOn() != null) {
            this.expressService.getNode().addDependency(props.getDependsOn());
        }
    }

    public Cluster getEcsCluster() {
        return ecsCluster;
    }

    public CfnExpressGatewayService getExpressService() {
        return expressService;
    }

    public Role getInfrastructureRole() {
        return infrastructureRole;
    }

    public Role getTaskExecutionRole() {
        return taskExecutionRole;
    }

    public Role getTaskRole() {
        return taskRole;
    }

    // Props class
    public static class EcsExpressServiceProps {
        private final String appName;
        private final IVpc vpc;
        private final Database database;
        private final IDependable dependsOn;
        private final Consumer<Role> configureTaskRole;

        private EcsExpressServiceProps(Builder builder) {
            this.appName = builder.appName;
            this.vpc = builder.vpc;
            this.database = builder.database;
            this.dependsOn = builder.dependsOn;
            this.configureTaskRole = builder.configureTaskRole;
        }

        public static Builder builder() {
            return new Builder();
        }

        public String getAppName() { return appName; }
        public IVpc getVpc() { return vpc; }
        public Database getDatabase() { return database; }
        public IDependable getDependsOn() { return dependsOn; }
        public Consumer<Role> getConfigureTaskRole() { return configureTaskRole; }

        public static class Builder {
            private String appName;
            private IVpc vpc;
            private Database database;
            private IDependable dependsOn;
            private Consumer<Role> configureTaskRole;

            public Builder appName(String appName) { this.appName = appName; return this; }
            public Builder vpc(IVpc vpc) { this.vpc = vpc; return this; }
            public Builder database(Database database) { this.database = database; return this; }
            public Builder dependsOn(IDependable dependsOn) { this.dependsOn = dependsOn; return this; }
            public Builder configureTaskRole(Consumer<Role> configureTaskRole) { this.configureTaskRole = configureTaskRole; return this; }

            public EcsExpressServiceProps build() {
                return new EcsExpressServiceProps(this);
            }
        }
    }
}
