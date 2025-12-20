package sample.com.constructs;

import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.ecr.TagMutability;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.s3.IBucket;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * Unicorn construct for workshop-specific resources.
 * Uses "unicorn*" naming convention for compatibility with workshop content.
 *
 * Contains:
 * - ECR repository (unicorn-store-spring)
 * - EKS Pod Identity role (unicornstore-eks-pod-role)
 * - ECS task roles (unicornstore-ecs-task-role, unicornstore-ecs-task-execution-role)
 * - Database schema setup (unicorns table)
 */
public class Unicorn extends Construct {

    // ECR Repository
    private Repository ecrRepository;

    // EKS Roles
    private Role eksPodRole;

    // ECS Roles
    private Role ecsTaskRole;
    private Role ecsTaskExecutionRole;

    // Database Setup
    private CustomResource databaseSetupResource;

    public Unicorn(final Construct scope, final String id, final UnicornProps props) {
        super(scope, id);

        // === ECR REPOSITORY ===
        this.ecrRepository = Repository.Builder.create(this, "UnicornStoreRepository")
            .repositoryName("unicorn-store-spring")
            .imageScanOnPush(true)
            .imageTagMutability(TagMutability.MUTABLE)
            .removalPolicy(RemovalPolicy.DESTROY)
            .emptyOnDelete(true)
            .build();

        // === EKS ROLES ===
        if (props.isEksRolesEnabled()) {
            createEksRoles(props);
        }

        // === ECS ROLES ===
        if (props.isEcsRolesEnabled()) {
            createEcsRoles(props);
        }

        // === DATABASE SETUP ===
        if (props.getDatabase() != null) {
            createDatabaseSetup(props);
        }
    }

    /**
     * Creates database setup Lambda and custom resource to initialize unicorns table.
     */
    private void createDatabaseSetup(UnicornProps props) {
        Database database = props.getDatabase();

        // Create database setup Lambda function
        Function databaseSetupFunction = Function.Builder.create(this, "UnicornStoreDatabaseSetupFunction")
            .code(Code.fromInline(loadFile("/lambda/database-setup.py")))
            .handler("index.lambda_handler")
            .runtime(Runtime.PYTHON_3_13)
            .functionName("unicornstore-database-setup")
            .timeout(Duration.minutes(3))
            .vpc(props.getVpc())
            .securityGroups(List.of(database.getDatabaseSecurityGroup()))
            .build();

        // Grant permissions to setup function
        database.getDatabaseSecret().grantRead(databaseSetupFunction);
        database.getDatabase().grantDataApiAccess(databaseSetupFunction);

        // Create custom resource for database setup
        this.databaseSetupResource = CustomResource.Builder.create(this, "UnicornStoreDatabaseSetupResource")
            .serviceToken(databaseSetupFunction.getFunctionArn())
            .properties(Map.of(
                "SecretName", database.getDatabaseSecret().getSecretName(),
                "SqlStatements", loadFile("/unicorns.sql")
            ))
            .build();
        databaseSetupResource.getNode().addDependency(database.getDatabase());
    }

    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    /**
     * Creates EKS Pod Identity role with permissions for:
     * - X-Ray tracing
     * - CloudWatch metrics
     * - Bedrock AI access
     * - S3 bucket access
     * - Database secrets access
     */
    private void createEksRoles(UnicornProps props) {
        ServicePrincipal eksPods = ServicePrincipal.Builder.create("pods.eks.amazonaws.com")
            .build();

        // EKS Pod Identity role
        this.eksPodRole = Role.Builder.create(this, "UnicornStoreEksPodRole")
            .roleName("unicornstore-eks-pod-role")
            .assumedBy(eksPods)
            .description("EKS Pod Identity role for Unicorn Store application")
            .build();

        // Add sts:TagSession for Pod Identity
        eksPodRole.getAssumeRolePolicy().addStatements(
            PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .principals(List.of(eksPods))
                .actions(List.of("sts:TagSession"))
                .build()
        );

        // X-Ray tracing
        eksPodRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());

        // CloudWatch Agent
        eksPodRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy"));

        // Bedrock AI access
        eksPodRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess"));

        // S3 bucket access (if provided)
        if (props.getWorkshopBucket() != null) {
            eksPodRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("s3:ListBucket", "s3:GetObject", "s3:PutObject"))
                .resources(List.of(
                    props.getWorkshopBucket().getBucketArn(),
                    props.getWorkshopBucket().getBucketArn() + "/*"
                ))
                .build());
        }

        // Database secrets access (if provided)
        if (props.getDatabase() != null) {
            props.getDatabase().getDatabaseSecret().grantRead(eksPodRole);
            props.getDatabase().getParamDBConnectionString().grantRead(eksPodRole);
        }
    }

    /**
     * Creates ECS task roles with permissions for:
     * - X-Ray tracing
     * - CloudWatch logs
     * - SSM parameter access
     * - Database secrets access
     */
    private void createEcsRoles(UnicornProps props) {
        ServicePrincipal ecsTasks = ServicePrincipal.Builder.create("ecs-tasks.amazonaws.com")
            .build();

        // OpenTelemetry policy for observability
        PolicyStatement otelPolicy = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream",
                "logs:DescribeLogStreams", "logs:DescribeLogGroups", "logs:PutRetentionPolicy",
                "xray:PutTraceSegments", "xray:PutTelemetryRecords",
                "xray:GetSamplingRules", "xray:GetSamplingTargets", "xray:GetSamplingStatisticSummaries",
                "cloudwatch:PutMetricData", "ssm:GetParameters"
            ))
            .resources(List.of("*"))
            .build();

        // ECS Task Role
        this.ecsTaskRole = Role.Builder.create(this, "UnicornStoreEcsTaskRole")
            .roleName("unicornstore-ecs-task-role")
            .assumedBy(ecsTasks)
            .description("ECS task role for Unicorn Store application")
            .build();

        ecsTaskRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());

        ecsTaskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("CloudWatchLogsFullAccess"));
        ecsTaskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMReadOnlyAccess"));
        ecsTaskRole.addToPolicy(otelPolicy);

        // Database secrets access (if provided)
        if (props.getDatabase() != null) {
            props.getDatabase().getDatabaseSecret().grantRead(ecsTaskRole);
            props.getDatabase().getSecretPassword().grantRead(ecsTaskRole);
            props.getDatabase().getParamDBConnectionString().grantRead(ecsTaskRole);
        }

        // ECS Task Execution Role
        this.ecsTaskExecutionRole = Role.Builder.create(this, "UnicornStoreEcsTaskExecutionRole")
            .roleName("unicornstore-ecs-task-execution-role")
            .assumedBy(ecsTasks)
            .description("ECS task execution role for Unicorn Store application")
            .build();

        ecsTaskExecutionRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("logs:CreateLogGroup"))
            .resources(List.of("*"))
            .build());

        ecsTaskExecutionRole.addManagedPolicy(
            ManagedPolicy.fromAwsManagedPolicyName("service-role/AmazonECSTaskExecutionRolePolicy"));
        ecsTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("CloudWatchLogsFullAccess"));
        ecsTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMReadOnlyAccess"));
        ecsTaskExecutionRole.addToPolicy(otelPolicy);

        // Database secrets access for execution role (if provided)
        if (props.getDatabase() != null) {
            props.getDatabase().getDatabaseSecret().grantRead(ecsTaskExecutionRole);
            props.getDatabase().getSecretPassword().grantRead(ecsTaskExecutionRole);
        }
    }

    // Getters
    public Repository getEcrRepository() {
        return ecrRepository;
    }

    public Role getEksPodRole() {
        return eksPodRole;
    }

    public Role getEcsTaskRole() {
        return ecsTaskRole;
    }

    public Role getEcsTaskExecutionRole() {
        return ecsTaskExecutionRole;
    }

    // Props class
    public static class UnicornProps {
        private final boolean eksRolesEnabled;
        private final boolean ecsRolesEnabled;
        private final Database database;
        private final IBucket workshopBucket;
        private final software.amazon.awscdk.services.ec2.IVpc vpc;

        private UnicornProps(Builder builder) {
            this.eksRolesEnabled = builder.eksRolesEnabled;
            this.ecsRolesEnabled = builder.ecsRolesEnabled;
            this.database = builder.database;
            this.workshopBucket = builder.workshopBucket;
            this.vpc = builder.vpc;
        }

        public static Builder builder() {
            return new Builder();
        }

        public boolean isEksRolesEnabled() {
            return eksRolesEnabled;
        }

        public boolean isEcsRolesEnabled() {
            return ecsRolesEnabled;
        }

        public Database getDatabase() {
            return database;
        }

        public IBucket getWorkshopBucket() {
            return workshopBucket;
        }

        public software.amazon.awscdk.services.ec2.IVpc getVpc() {
            return vpc;
        }

        public static class Builder {
            private boolean eksRolesEnabled = false;
            private boolean ecsRolesEnabled = false;
            private Database database;
            private IBucket workshopBucket;
            private software.amazon.awscdk.services.ec2.IVpc vpc;

            public Builder eksRolesEnabled(boolean eksRolesEnabled) {
                this.eksRolesEnabled = eksRolesEnabled;
                return this;
            }

            public Builder ecsRolesEnabled(boolean ecsRolesEnabled) {
                this.ecsRolesEnabled = ecsRolesEnabled;
                return this;
            }

            public Builder database(Database database) {
                this.database = database;
                return this;
            }

            public Builder workshopBucket(IBucket workshopBucket) {
                this.workshopBucket = workshopBucket;
                return this;
            }

            public Builder vpc(software.amazon.awscdk.services.ec2.IVpc vpc) {
                this.vpc = vpc;
                return this;
            }

            public UnicornProps build() {
                return new UnicornProps(this);
            }
        }
    }
}
