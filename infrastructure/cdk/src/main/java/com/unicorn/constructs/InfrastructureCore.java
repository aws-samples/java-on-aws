package com.unicorn.constructs;

// import software.amazon.awscdk.CfnOutput;
// import software.amazon.awscdk.CfnOutputProps;
// import software.amazon.awscdk.*;
// import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.Vpc;
import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.ec2.Peer;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.ec2.SubnetConfiguration;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.ISecurityGroup;
import software.amazon.awscdk.services.ec2.SecurityGroupProps;
import software.amazon.awscdk.services.ec2.IpAddresses;
import software.amazon.awscdk.services.events.EventBus;
// import software.amazon.awscdk.services.rds.*;
import software.amazon.awscdk.services.rds.AuroraPostgresClusterEngineProps;
import software.amazon.awscdk.services.rds.ServerlessV2ClusterInstanceProps;
import software.amazon.awscdk.services.rds.AuroraPostgresEngineVersion;
import software.amazon.awscdk.services.rds.Credentials;
import software.amazon.awscdk.services.rds.ClusterInstance;
import software.amazon.awscdk.services.rds.DatabaseCluster;
import software.amazon.awscdk.services.rds.DatabaseClusterEngine;
import software.amazon.awscdk.services.rds.DatabaseSecret;
import software.amazon.awscdk.services.ssm.ParameterTier;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.amazon.awscdk.services.secretsmanager.Secret;
import software.amazon.awscdk.SecretValue;
import software.amazon.awscdk.SecretsManagerSecretOptions;
import software.constructs.Construct;

import java.util.Arrays;
import java.util.List;

public class InfrastructureCore extends Construct {

    private final DatabaseSecret databaseSecret;
    private final DatabaseCluster database;
    private final EventBus eventBridge;
    private final IVpc vpc;
    private final ISecurityGroup applicationSecurityGroup;
    private final StringParameter paramJdbc;
    private final Secret secretPassword;

    public InfrastructureCore(final Construct scope, final String id) {
        super(scope, id);

        vpc = createUnicornVpc();
        databaseSecret = createDatabaseSecret();
        database = createRDSPostgresInstance(vpc, databaseSecret);
        eventBridge = createEventBus();
        applicationSecurityGroup = new SecurityGroup(this, "ApplicationSecurityGroup",
            SecurityGroupProps
                .builder()
                .securityGroupName("unicornstore-application-sg")
                .vpc(vpc)
                .allowAllOutbound(true)
                .build());

        paramJdbc = createParamJdbc();
        secretPassword = createSecretPassword();

        // createEventBridgeVpcEndpoint();
        // createDynamoDBVpcEndpoint();
    }

    private EventBus createEventBus() {
        return EventBus.Builder.create(this, "UnicornEventBus")
                .eventBusName("unicorns")
                .build();
    }

    private SecurityGroup createDatabaseSecurityGroup(IVpc vpc) {
        var databaseSecurityGroup = SecurityGroup.Builder.create(this, "DatabaseSG")
                .securityGroupName("unicornstore-db-sg")
                .allowAllOutbound(false)
                .vpc(vpc)
                .build();

        databaseSecurityGroup.addIngressRule(
                Peer.ipv4("10.0.0.0/16"),
                Port.tcp(5432),
                "Allow Database Traffic from local network");

        // databaseSecurityGroup.addIngressRule(
        //         Peer.ipv4("192.168.0.0/16"),
        //         Port.tcp(5432),
        //         "Allow Database Traffic from IDE network");

        return databaseSecurityGroup;
    }

    private DatabaseCluster createRDSPostgresInstance(IVpc vpc, DatabaseSecret databaseSecret) {

        var databaseSecurityGroup = createDatabaseSecurityGroup(vpc);

        var dbCluster = DatabaseCluster.Builder.create(this, "UnicornStoreDatabase")
            .engine(DatabaseClusterEngine.auroraPostgres(
                AuroraPostgresClusterEngineProps.builder().version(AuroraPostgresEngineVersion.VER_16_4).build()))
            .serverlessV2MinCapacity(0.5)
            .serverlessV2MaxCapacity(4)
            .writer(ClusterInstance.serverlessV2("UnicornStoreDatabaseWriter", ServerlessV2ClusterInstanceProps.builder()
                .instanceIdentifier("unicornstore-db-writer")
                .autoMinorVersionUpgrade(true)
                .build()))
            .enableDataApi(true)
            .defaultDatabaseName("unicorns")
            .clusterIdentifier("unicornstore-db-cluster")
            .instanceIdentifierBase("unicornstore-db-instance")
            .vpc(vpc)
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .securityGroups(List.of(databaseSecurityGroup))
            .credentials(Credentials.fromSecret(databaseSecret))
            .build();

            return dbCluster;
        // var engine = DatabaseInstanceEngine.postgres(PostgresInstanceEngineProps.builder().version(PostgresEngineVersion.VER_16).build());

        // return DatabaseInstance.Builder.create(this, "UnicornInstance")
        //         .engine(engine)
        //         .vpc(vpc)
        //         .allowMajorVersionUpgrade(true)
        //         .backupRetention(Duration.days(0))
        //         .databaseName("unicorns")
        //         .instanceIdentifier("UnicornInstance")
        //         .instanceType(InstanceType.of(InstanceClass.BURSTABLE3, InstanceSize.MEDIUM))
        //         .vpcSubnets(SubnetSelection.builder()
        //                 .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
        //                 .build())
        //         .securityGroups(List.of(databaseSecurityGroup))
        //         .credentials(Credentials.fromSecret(databaseSecret))
        //         .build();
    }

    private DatabaseSecret createDatabaseSecret() {
        return DatabaseSecret.Builder
                .create(this, "postgres")
                .secretName("unicornstore-db-secret")
                .username("postgres").build();
    }

    private IVpc createUnicornVpc() {
        // IVpc vpc = Vpc.Builder.create(this, "UnicornVpc")
        //         .vpcName("UnicornVPC")
        //         .natGateways(0)
        //         .build();
        IVpc vpc = Vpc.Builder.create(this, "UnicornVpc")
            .vpcName("unicornstore-vpc")
            .ipAddresses(IpAddresses.cidr("10.0.0.0/16"))
            .maxAzs(2)  // Use 2 Availability Zones
            .subnetConfiguration(Arrays.asList(
                SubnetConfiguration.builder()
                    .name("Public")
                    .subnetType(SubnetType.PUBLIC)
                    .cidrMask(24)
                    .build(),
                SubnetConfiguration.builder()
                    .name("Private")
                    .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                    .cidrMask(24)
                    .build()
                ))
            .natGateways(1)
            .build();

        // new CfnOutput(this, "UnicornStoreVpcId", CfnOutputProps.builder().value(vpc.getVpcId()).build());
        return vpc;
    }

    private Secret createSecretPassword() {
        // Separate password value for services which cannot get specific field from Secret json
        return Secret.Builder.create(this, "dbSecretPassword")
            .secretName("unicornstore-db-password-secret")
            .secretStringValue(SecretValue.secretsManager(databaseSecret.getSecretName(),
                SecretsManagerSecretOptions.builder().jsonField("password").build()))
            .build();
    }

    public Secret getSecretPassword() {
        return secretPassword;
    }

    private StringParameter createParamJdbc() {
        return StringParameter.Builder.create(this, "SsmParameterDatabaseJDBCConnectionString")
            .allowedPattern(".*")
            .description("database JDBC Connection String")
            .parameterName("unicornstore-db-connection-string")
            .stringValue(getDatabaseJDBCConnectionString())
            .tier(ParameterTier.STANDARD)
            .build();
    }

    public StringParameter getParamJdbc() {
        return paramJdbc;
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

    public DatabaseSecret getDatabaseSecret(){
        return databaseSecret;
    }

    public DatabaseCluster getDatabase() {
        return database;
    }

    public String getDatabaseJDBCConnectionString(){
        return "jdbc:postgresql://" + database.getClusterEndpoint().getHostname() + ":5432/unicorns";
        // return "jdbc:postgresql://" + database.getDbInstanceEndpointAddress() + ":5432/unicorns";
    }

    // private IInterfaceVpcEndpoint createEventBridgeVpcEndpoint() {
    //     return InterfaceVpcEndpoint.Builder.create(this, "EventBridgeEndpoint")
    //             .service(InterfaceVpcEndpointAwsService.EVENTBRIDGE)
    //             .vpc(this.getVpc())
    //             .build();
    // }

    // private IGatewayVpcEndpoint createDynamoDBVpcEndpoint() {
    //     return GatewayVpcEndpoint.Builder.create(this, "DynamoDBVpcEndpoint")
    //             .service(GatewayVpcEndpointAwsService.DYNAMODB)
    //             .vpc(this.getVpc())
    //             .build();
    // }

}
