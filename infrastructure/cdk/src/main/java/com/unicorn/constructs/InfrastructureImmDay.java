package com.unicorn.constructs;

import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.ArnPrincipal;
import software.amazon.awscdk.services.iam.CfnServiceLinkedRole;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.RemovalPolicy;
// import software.amazon.awscdk.services.apprunner.alpha.VpcConnector;
import software.constructs.Construct;

import java.util.List;

// Additional infrastructure for Java on AWS Immersion Day
public class InfrastructureImmDay extends Construct {

    private final InfrastructureCore infrastructureCore;

    private final Repository ecrRepository;

    public InfrastructureImmDay(final Construct scope, final String id,
        final InfrastructureCore infrastructureCore) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureCore = infrastructureCore;

        ecrRepository = createEcr();

        createRolesAppRunner();
        // createVpcConnector();
        createRolesEcs();
        createRolesEks();
    }

    private Repository createEcr() {
        return Repository.Builder.create(this, "UnicornStoreEcr")
            .repositoryName("unicorn-store-spring")
            .imageScanOnPush(false)
            .removalPolicy(RemovalPolicy.DESTROY)
            .emptyOnDelete(true)  // This will force delete all images when repository is deleted
            .build();
    }

    public Repository getEcrRepository() {
        return ecrRepository;
    }

    // private void createVpcConnector() {
    //     VpcConnector.Builder.create(this, "UnicornStoreVpcConnector")
    //         .vpc(infrastructureCore.getVpc())
    //         .vpcSubnets(SubnetSelection.builder()
    //             .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
    //             .build())
    //         .vpcConnectorName("unicornstore-vpc-connector")
    //         .build();
    // }

    private void createRolesAppRunner() {
        var unicornStoreApprunnerRole = Role.Builder.create(this, "UnicornStoreApprunnerRole")
            .roleName("unicornstore-apprunner-role")
            .assumedBy(new ServicePrincipal("tasks.apprunner.amazonaws.com")).build();
        unicornStoreApprunnerRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());
        infrastructureCore.getEventBridge().grantPutEventsTo(unicornStoreApprunnerRole);
        infrastructureCore.getDatabaseSecret().grantRead(unicornStoreApprunnerRole);
        infrastructureCore.getSecretPassword().grantRead(unicornStoreApprunnerRole);
        infrastructureCore.getParamJdbc().grantRead(unicornStoreApprunnerRole);

        var appRunnerECRAccessRole = Role.Builder.create(this, "UnicornStoreApprunnerEcrAccessRole")
            .roleName("unicornstore-apprunner-ecr-access-role")
            .assumedBy(new ServicePrincipal("build.apprunner.amazonaws.com")).build();
        appRunnerECRAccessRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreApprunnerEcrAccessRole-" + "AWSAppRunnerServicePolicyForECRAccess",
            "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"));

        // Create the App Runner service-linked role
        CfnServiceLinkedRole appRunnerServiceLinkedRole = CfnServiceLinkedRole.Builder.create(this, "AppRunnerServiceLinkedRole")
            .awsServiceName("apprunner.amazonaws.com")
            .description("Service-linked role for AWS App Runner service")
            .build();
    }

    private void createRolesEcs() {
        var AWSOpenTelemetryPolicy = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream",
                    "logs:DescribeLogStreams", "logs:DescribeLogGroups",
                    "logs:PutRetentionPolicy", "xray:PutTraceSegments",
                    "xray:PutTelemetryRecords", "xray:GetSamplingRules",
                    "xray:GetSamplingTargets", "xray:GetSamplingStatisticSummaries",
                    "cloudwatch:PutMetricData", "ssm:GetParameters"))
            .resources(List.of("*")).build();

        var unicornStoreEscTaskRole = Role.Builder.create(this, "UnicornStoreEcsTaskRole")
            .roleName("unicornstore-ecs-task-role")
            .assumedBy(new ServicePrincipal("ecs-tasks.amazonaws.com")).build();
        unicornStoreEscTaskRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());
        unicornStoreEscTaskRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEcsTaskRole-" + "CloudWatchLogsFullAccess",
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"));
        unicornStoreEscTaskRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEcsTaskRole-" + "AmazonSSMReadOnlyAccess",
            "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"));
        unicornStoreEscTaskRole.addToPolicy(AWSOpenTelemetryPolicy);

        infrastructureCore.getEventBridge().grantPutEventsTo(unicornStoreEscTaskRole);
        infrastructureCore.getDatabaseSecret().grantRead(unicornStoreEscTaskRole);
        infrastructureCore.getSecretPassword().grantRead(unicornStoreEscTaskRole);
        infrastructureCore.getParamJdbc().grantRead(unicornStoreEscTaskRole);

        Role unicornStoreEscTaskExecutionRole = Role.Builder.create(this, "UnicornStoreEcsTaskExecutionRole")
            .roleName("unicornstore-ecs-task-execution-role")
            .assumedBy(new ServicePrincipal("ecs-tasks.amazonaws.com")).build();
        unicornStoreEscTaskExecutionRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("logs:CreateLogGroup"))
            .resources(List.of("*"))
            .build());
        unicornStoreEscTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEcsTaskExecutionRole-" + "AmazonECSTaskExecutionRolePolicy",
            "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"));
        unicornStoreEscTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEcsTaskExecutionRole-" + "CloudWatchLogsFullAccess",
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"));
        unicornStoreEscTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEcsTaskExecutionRole-" + "AmazonSSMReadOnlyAccess",
            "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"));
        unicornStoreEscTaskExecutionRole.addToPolicy(AWSOpenTelemetryPolicy);

        infrastructureCore.getEventBridge().grantPutEventsTo(unicornStoreEscTaskExecutionRole);
        infrastructureCore.getDatabaseSecret().grantRead(unicornStoreEscTaskExecutionRole);
        infrastructureCore.getSecretPassword().grantRead(unicornStoreEscTaskExecutionRole);
    }

    private void createRolesEks() {
        ServicePrincipal eksPods = new ServicePrincipal("pods.eks.amazonaws.com");

        // EKS Pod Identity role
        var unicornStoreEksPodRole = Role.Builder.create(this, "UnicornStoreEksPodRole")
            .roleName("unicornstore-eks-pod-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        unicornStoreEksPodRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());
        unicornStoreEksPodRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEksPodRole-" + "CloudWatchAgentServerPolicy",
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"));

        infrastructureCore.getEventBridge().grantPutEventsTo(unicornStoreEksPodRole);
        infrastructureCore.getDatabaseSecret().grantRead(unicornStoreEksPodRole);
        infrastructureCore.getParamJdbc().grantRead(unicornStoreEksPodRole);

        var dbSecretPolicy = ManagedPolicy.Builder.create(this, "UnicornStoreDbSecretsManagerPolicy")
            .managedPolicyName("unicornstore-db-secret-policy")
            .statements(List.of(
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .actions(List.of("secretsmanager:ListSecrets"))
                    .resources(List.of("*"))
                    .build(),
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .actions(List.of(
                            "secretsmanager:GetResourcePolicy",
                            "secretsmanager:DescribeSecret",
                            "secretsmanager:GetSecretValue",
                            "secretsmanager:ListSecretVersionIds"
                    ))
                    .resources(List.of(infrastructureCore.getDatabaseSecret().getSecretFullArn()))
                    .build()
            ))
            .build();

        // External Secrets Operator roles
        Role unicornStoreEksEsoRole = Role.Builder.create(this, "UnicornStoreEksEsoRole")
            .roleName("unicornstore-eks-eso-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        ArnPrincipal unicornStoreEksEsoRolePrincipal = new ArnPrincipal(unicornStoreEksEsoRole.getRoleArn());

        Role unicornStoreEksEsoSmRole = Role.Builder.create(this, "UnicornStoreEksEsoSmRole")
            .roleName("unicornstore-eks-eso-sm-role")
            .assumedBy(unicornStoreEksEsoRolePrincipal.withSessionTags())
            .build();
        unicornStoreEksEsoSmRole.addManagedPolicy(dbSecretPolicy);
    }
}
