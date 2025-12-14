package sample.com.constructs;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.SecretValue;
import software.amazon.awscdk.SecretsManagerSecretOptions;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.ec2.Peer;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.ec2.ISecurityGroup;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
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
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

public class Database extends Construct {

    private final DatabaseSecret databaseSecret;
    private final DatabaseCluster database;
    private final ISecurityGroup databaseSecurityGroup;

    private final StringParameter paramDBConnectionString;
    private final Secret secretPassword;
    private final CustomResource databaseSetupResource;

    public Database(final Construct scope, final String id, final IVpc vpc) {
        super(scope, id);

        // Create database secret with universal naming
        databaseSecret = DatabaseSecret.Builder
            .create(this, "DatabaseSecret")
            .secretName("workshop-db-secret")
            .username("postgres")
            .build();

        // Create database security group
        databaseSecurityGroup = SecurityGroup.Builder.create(this, "DatabaseSG")
            .securityGroupName("workshop-db-sg")
            .allowAllOutbound(false)
            .vpc(vpc)
            .build();

        databaseSecurityGroup.addIngressRule(
            Peer.ipv4("10.0.0.0/16"),
            Port.tcp(5432),
            "Allow Database Traffic from local network");



        // Create Aurora PostgreSQL cluster with universal naming
        database = DatabaseCluster.Builder.create(this, "DatabaseCluster")
            .engine(DatabaseClusterEngine.auroraPostgres(
                AuroraPostgresClusterEngineProps.builder()
                    .version(AuroraPostgresEngineVersion.VER_16_4)
                    .build()))
            .serverlessV2MinCapacity(0.5)
            .serverlessV2MaxCapacity(4)
            .writer(ClusterInstance.serverlessV2("DatabaseWriter", ServerlessV2ClusterInstanceProps.builder()
                .instanceIdentifier("workshop-db-writer")
                .autoMinorVersionUpgrade(true)
                .build()))
            .enableDataApi(true)
            .defaultDatabaseName("workshop")
            .clusterIdentifier("workshop-db-cluster")
            .vpc(vpc)
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .securityGroups(List.of(databaseSecurityGroup))
            .credentials(Credentials.fromSecret(databaseSecret))
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Create separate password secret for services that need plain password
        secretPassword = Secret.Builder.create(this, "DatabasePasswordSecret")
            .secretName("workshop-db-password-secret")
            .secretStringValue(SecretValue.secretsManager(databaseSecret.getSecretName(),
                SecretsManagerSecretOptions.builder().jsonField("password").build()))
            .build();

        // Create parameter store entry for connection string
        paramDBConnectionString = StringParameter.Builder.create(this, "DatabaseConnectionString")
            .allowedPattern(".*")
            .description("Database Connection String")
            .parameterName("workshop-db-connection-string")
            .stringValue(getConnectionString())
            .tier(ParameterTier.STANDARD)
            .build();

        // Create database setup Lambda function
        Function databaseSetupFunction = Function.Builder.create(this, "DatabaseSetupFunction")
            .code(Code.fromInline(loadFile("/lambda/database-setup.py")))
            .handler("index.lambda_handler")
            .runtime(Runtime.PYTHON_3_13)
            .functionName("workshop-db-setup")
            .timeout(Duration.minutes(3))
            .vpc(vpc)
            .securityGroups(List.of(databaseSecurityGroup))
            .build();

        // Grant permissions to setup function
        databaseSecret.grantRead(databaseSetupFunction);
        database.grantDataApiAccess(databaseSetupFunction);

        // Create custom resource for database setup
        databaseSetupResource = CustomResource.Builder.create(this, "DatabaseSetupResource")
            .serviceToken(databaseSetupFunction.getFunctionArn())
            .properties(Map.of(
                "SecretName", databaseSecret.getSecretName(),
                "SqlStatements", loadFile("/schema.sql")
            ))
            .build();
        databaseSetupResource.getNode().addDependency(database);
    }

    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    public String getConnectionString() {
        return "jdbc:postgresql://" + database.getClusterEndpoint().getHostname() + ":5432/workshop";
    }

    // Getters
    public DatabaseSecret getDatabaseSecret() {
        return databaseSecret;
    }

    public DatabaseCluster getDatabase() {
        return database;
    }

    public ISecurityGroup getDatabaseSecurityGroup() {
        return databaseSecurityGroup;
    }

    public StringParameter getParamDBConnectionString() {
        return paramDBConnectionString;
    }

    public Secret getSecretPassword() {
        return secretPassword;
    }

    public String getDatabaseSecretString() {
        return databaseSecret.secretValueFromJson("password").toString();
    }
}