package sample.com.constructs;

import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.ecs.CfnExpressGatewayService;
import software.amazon.awscdk.services.ecs.Cluster;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.logs.LogGroup;
import software.constructs.Construct;
import software.constructs.IDependable;

import java.util.List;

/**
 * ECS Express Mode service construct for Spring AI agents.
 * Creates ECS cluster and ECS Express Gateway Service with ALB.
 * ECR repos are created via create-on-push (EcrRegistry construct).
 * Reuses Unicorn's ECS roles and adds Bedrock access for AI capabilities.
 */
public class EcsExpressService extends Construct {

    private final Cluster ecsCluster;
    private final CfnExpressGatewayService expressService;

    public EcsExpressService(final Construct scope, final String id, final EcsExpressServiceProps props) {
        super(scope, id);

        String appName = props.getAppName();

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

        // Add Bedrock access to task role for AI capabilities
        Role taskRole = props.getUnicorn().getEcsTaskRole();
        taskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockFullAccess"));

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
            .infrastructureRoleArn(props.getUnicorn().getEcsInfrastructureRole().getRoleArn())
            .executionRoleArn(props.getUnicorn().getEcsTaskExecutionRole().getRoleArn())
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

    // Props class
    public static class EcsExpressServiceProps {
        private final String appName;
        private final IVpc vpc;
        private final Database database;
        private final Unicorn unicorn;
        private final IDependable dependsOn;

        private EcsExpressServiceProps(Builder builder) {
            this.appName = builder.appName;
            this.vpc = builder.vpc;
            this.database = builder.database;
            this.unicorn = builder.unicorn;
            this.dependsOn = builder.dependsOn;
        }

        public static Builder builder() {
            return new Builder();
        }

        public String getAppName() { return appName; }
        public IVpc getVpc() { return vpc; }
        public Database getDatabase() { return database; }
        public Unicorn getUnicorn() { return unicorn; }
        public IDependable getDependsOn() { return dependsOn; }

        public static class Builder {
            private String appName;
            private IVpc vpc;
            private Database database;
            private Unicorn unicorn;
            private IDependable dependsOn;

            public Builder appName(String appName) { this.appName = appName; return this; }
            public Builder vpc(IVpc vpc) { this.vpc = vpc; return this; }
            public Builder database(Database database) { this.database = database; return this; }
            public Builder unicorn(Unicorn unicorn) { this.unicorn = unicorn; return this; }
            public Builder dependsOn(IDependable dependsOn) { this.dependsOn = dependsOn; return this; }

            public EcsExpressServiceProps build() {
                return new EcsExpressServiceProps(this);
            }
        }
    }
}
