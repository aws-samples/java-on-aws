package com.unicorn.core;

import com.unicorn.constructs.DatabaseSetupConstruct;
import software.constructs.Construct;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnOutputProps;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.SecretValue;
import software.amazon.awscdk.SecretsManagerSecretOptions;
import software.amazon.awscdk.Tags;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.events.EventBus;
import software.amazon.awscdk.services.rds.DatabaseSecret;
import software.amazon.awscdk.services.rds.DatabaseInstance;
import software.amazon.awscdk.services.rds.PostgresEngineVersion;
import software.amazon.awscdk.services.rds.PostgresInstanceEngineProps;
import software.amazon.awscdk.services.rds.DatabaseInstanceEngine;
import software.amazon.awscdk.services.rds.Credentials;
import software.amazon.awscdk.services.ssm.*;
import software.amazon.awscdk.services.secretsmanager.*;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.User;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ArnPrincipal;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.RemovalPolicy;

import java.util.List;

public class InfrastructureStack extends Stack {

    private final DatabaseSecret databaseSecret;
    private final Secret secretPassword;
    private final StringParameter paramJdbc;
    private final DatabaseInstance database;
    private final EventBus eventBridge;
    private final IVpc vpc;
    private final ISecurityGroup applicationSecurityGroup;


    public InfrastructureStack(final Construct scope, final String id, final StackProps props,
            final VpcStack vpcStack) {
        super(scope, id, props);

        vpc = vpcStack.getVpc();
        new CfnOutput(this, "idUnicornStoreVPC", CfnOutputProps.builder()
                .value(vpc.getVpcId())
                .build());
        Tags.of(vpc).add("unicorn", "true");
        new CfnOutput(this, "arnUnicornStoreVPC", CfnOutputProps.builder()
                .value(vpc.getVpcArn())
                .exportName("arnUnicornStoreVPC")
                .build());
        databaseSecret = createDatabaseSecret();
        new CfnOutput(this, "arnUnicornStoreDbSecret", CfnOutputProps.builder()
                .value(databaseSecret.getSecretFullArn())
                .exportName("arnUnicornStoreDbSecret")
                .build());
        secretPassword = Secret.Builder.create(this, "dbSecretPassword")
            .secretName("unicornstore-db-secret-password")
            .secretStringValue(SecretValue.secretsManager(databaseSecret.getSecretName(), SecretsManagerSecretOptions.builder().jsonField("password").build()))
            .build();
        new CfnOutput(this, "arnUnicornStoreDbSecretPassword", CfnOutputProps.builder()
                .value(secretPassword.getSecretFullArn())
                .exportName("arnUnicornStoreDbSecretPassword")
                .build());
        database = createRDSPostgresInstance(vpc, databaseSecret);
        new CfnOutput(this, "arnUnicornStoreDbInstance", CfnOutputProps.builder()
            .value(database.getInstanceArn())
            .exportName("arnUnicornStoreDbInstance")
            .build());
        new CfnOutput(this, "databaseJDBCConnectionString", CfnOutputProps.builder()
            .value(getDatabaseJDBCConnectionString())
            .exportName("databaseJDBCConnectionString")
            .build());
        paramJdbc = StringParameter.Builder.create(this, "SsmParameterDatabaseJDBCConnectionString")
            .allowedPattern(".*")
            .description("databaseJDBCConnectionString")
            .parameterName("databaseJDBCConnectionString")
            .stringValue(getDatabaseJDBCConnectionString())
            .tier(ParameterTier.STANDARD)
            .build();
        new CfnOutput(this, "arnSsmParameterDatabaseJDBCConnectionString", CfnOutputProps.builder()
            .value(paramJdbc.getParameterArn())
            .exportName("arnSsmParameterDatabaseJDBCConnectionString")
            .build());
        new CfnOutput(this, "ssmParameterDatabaseJDBCConnectionString", CfnOutputProps.builder()
            .value(paramJdbc.getParameterName())
            .exportName("ssmParameterDatabaseJDBCConnectionString")
            .build());
        eventBridge = createEventBus();
        new CfnOutput(this, "arnUnicornStoreEventBus", CfnOutputProps.builder()
            .value(eventBridge.getEventBusArn())
            .exportName("arnUnicornStoreEventBus")
            .build());
        applicationSecurityGroup = new SecurityGroup(this, "ApplicationSecurityGroup",
                SecurityGroupProps
                        .builder()
                        .securityGroupName("applicationSG")
                        .vpc(vpc)
                        .allowAllOutbound(true)
                        .build());

        new DatabaseSetupConstruct(this, "UnicornDatabaseConstruct");

        // User unicornStoreGitOpsUser = User.Builder.create(this, "unicorn-store-gitops")
        //     .userName("unicorn-store-gitops")
        //     .build();
        // unicornStoreGitOpsUser.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
        //     "unicornStoreGitOpsUser-" + "AWSCodeCommitPowerUser",
        //     "arn:aws:iam::aws:policy/AWSCodeCommitPowerUser"));

        Role unicornStoreApprunnerRole = Role.Builder.create(this, "unicornstore-apprunner-role")
            .roleName("unicornstore-apprunner-role")
            .assumedBy(new ServicePrincipal("tasks.apprunner.amazonaws.com")).build();
        unicornStoreApprunnerRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());

        // create ECR repository
        Repository unicornStoreECR = Repository.Builder.create(this, "unicornstore-ecr")
            .repositoryName("unicorn-store-spring")
            .imageScanOnPush(false)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        Role appRunnerECRAccessRole = Role.Builder.create(this, "unicornstore-apprunner-ecr-access-role")
            .roleName("unicornstore-apprunner-ecr-access-role")
            .assumedBy(new ServicePrincipal("build.apprunner.amazonaws.com")).build();
        appRunnerECRAccessRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-apprunner-ecr-access-role-" + "AWSAppRunnerServicePolicyForECRAccess",
            "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"));

        PolicyStatement AWSOpenTelemetryPolicy = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream",
                    "logs:DescribeLogStreams", "logs:DescribeLogGroups",
                    "logs:PutRetentionPolicy", "xray:PutTraceSegments",
                    "xray:PutTelemetryRecords", "xray:GetSamplingRules",
                    "xray:GetSamplingTargets", "xray:GetSamplingStatisticSummaries",
                    "cloudwatch:PutMetricData", "ssm:GetParameters"))
            .resources(List.of("*")).build();

        Role unicornStoreEscTaskRole = Role.Builder.create(this, "unicornstore-ecs-task-role")
            .roleName("unicornstore-ecs-task-role")
            .assumedBy(new ServicePrincipal("ecs-tasks.amazonaws.com")).build();
        unicornStoreEscTaskRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());
        unicornStoreEscTaskRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-ecs-task-role-" + "CloudWatchLogsFullAccess",
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"));
        unicornStoreEscTaskRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-ecs-task-role-" + "AmazonSSMReadOnlyAccess",
            "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"));
        unicornStoreEscTaskRole.addToPolicy(AWSOpenTelemetryPolicy);

        Role unicornStoreEscTaskExecutionRole = Role.Builder.create(this, "unicornstore-ecs-task-execution-role")
            .roleName("unicornstore-ecs-task-execution-role")
            .assumedBy(new ServicePrincipal("ecs-tasks.amazonaws.com")).build();
        unicornStoreEscTaskExecutionRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("logs:CreateLogGroup"))
            .resources(List.of("*"))
            .build());
        unicornStoreEscTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-ecs-task-execution-role-" + "AmazonECSTaskExecutionRolePolicy",
            "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"));
        unicornStoreEscTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-ecs-task-execution-role-" + "CloudWatchLogsFullAccess",
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"));
        unicornStoreEscTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-ecs-task-execution-role-" + "AmazonSSMReadOnlyAccess",
            "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"));
        unicornStoreEscTaskExecutionRole.addToPolicy(AWSOpenTelemetryPolicy);

        ServicePrincipal eksPods = new ServicePrincipal("pods.eks.amazonaws.com");

        Role unicornStoreEksEsoRole = Role.Builder.create(this, "unicornstore-eks-eso-role")
            .roleName("unicornstore-eks-eso-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        ArnPrincipal unicornStoreEksEsoRolePrincipal = new ArnPrincipal(unicornStoreEksEsoRole.getRoleArn());

        Role unicornStoreEksEsoSmRole = Role.Builder.create(this, "unicornstore-eks-eso-sm-role")
            .roleName("unicornstore-eks-eso-sm-role")
            .assumedBy(unicornStoreEksEsoRolePrincipal.withSessionTags())
            .build();
        unicornStoreEksEsoSmRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("secretsmanager:ListSecrets"))
            .resources(List.of("*"))
            .build());
        unicornStoreEksEsoSmRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:DescribeSecret",
                "secretsmanager:GetSecretValue",
                "secretsmanager:ListSecretVersionIds"
            ))
            .resources(List.of(databaseSecret.getSecretFullArn()))
            .build());

        Role unicornStoreEksPodRole = Role.Builder.create(this, "unicornstore-eks-pod-role")
            .roleName("unicornstore-eks-pod-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        unicornStoreEksPodRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());
        unicornStoreEksPodRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "unicornstore-eks-pod-role-" + "CloudWatchAgentServerPolicy",
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"));
        getEventBridge().grantPutEventsTo(unicornStoreEksPodRole);
        getParamJdbsc().grantRead(unicornStoreEksPodRole);

        getEventBridge().grantPutEventsTo(unicornStoreApprunnerRole);
        getEventBridge().grantPutEventsTo(unicornStoreEscTaskRole);
        getSecretPassword().grantRead(unicornStoreApprunnerRole);
        getSecretPassword().grantRead(unicornStoreEscTaskRole);
        getSecretPassword().grantRead(unicornStoreEscTaskExecutionRole);
        getParamJdbsc().grantRead(unicornStoreApprunnerRole);
        getParamJdbsc().grantRead(unicornStoreEscTaskRole);
        getParamJdbsc().grantRead(unicornStoreEscTaskExecutionRole);
    }

    private EventBus createEventBus() {
        return EventBus.Builder.create(this, "UnicornEventBus")
                .eventBusName("unicorns")
                .build();
    }

    private SecurityGroup createDatabaseSecurityGroup(IVpc vpc) {
        var databaseSecurityGroup = SecurityGroup.Builder.create(this, "DatabaseSG")
                .securityGroupName("DatabaseSG")
                .allowAllOutbound(false)
                .vpc(vpc)
                .build();

        databaseSecurityGroup.addIngressRule(
                Peer.ipv4("10.0.0.0/16"),
                Port.tcp(5432),
                "Allow Database Traffic from local network");

        databaseSecurityGroup.addIngressRule(
                Peer.ipv4("192.168.0.0/16"),
                Port.tcp(5432),
                "Allow Database Traffic from IDE network");

        return databaseSecurityGroup;
    }

    private DatabaseInstance createRDSPostgresInstance(IVpc vpc, DatabaseSecret databaseSecret) {

        var databaseSecurityGroup = createDatabaseSecurityGroup(vpc);
        var engine = DatabaseInstanceEngine.postgres(PostgresInstanceEngineProps.builder().version(PostgresEngineVersion.VER_16_3).build());

        return DatabaseInstance.Builder.create(this, "UnicornInstance")
                .engine(engine)
                .vpc(vpc)
                .allowMajorVersionUpgrade(true)
                .backupRetention(Duration.days(0))
                .databaseName("unicorns")
                .instanceIdentifier("UnicornInstance")
                .instanceType(InstanceType.of(InstanceClass.BURSTABLE3, InstanceSize.MEDIUM))
                .vpcSubnets(SubnetSelection.builder()
                        .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                        .build())
                .securityGroups(List.of(databaseSecurityGroup))
                .credentials(Credentials.fromSecret(databaseSecret))
                .build();
    }

    private DatabaseSecret createDatabaseSecret() {
        return DatabaseSecret.Builder
                .create(this, "postgres")
                .secretName("unicornstore-db-secret")
                .username("postgres").build();
    }

    public EventBus getEventBridge() {
        return eventBridge;
    }

    public IVpc getVpc() {
        return vpc;
    }

    public ISecurityGroup getApplicationSecurityGroup() {
        return applicationSecurityGroup;
    }

    public String getDatabaseSecretString(){
        return databaseSecret.secretValueFromJson("password").toString();
    }

    public String getDatabaseSecretKey(){
        return "password";
    }

    public DatabaseSecret getDatabaseSecret(){
        return databaseSecret;
    }

    public String getDatabaseSecretName(){
        return databaseSecret.getSecretName();
    }

    public String getDatabaseJDBCConnectionString(){
        return "jdbc:postgresql://" + database.getDbInstanceEndpointAddress() + ":5432/unicorns";
    }

    public Secret getSecretPassword(){
        return secretPassword;
    }

    public StringParameter getParamJdbsc(){
        return paramJdbc;
    }
}
