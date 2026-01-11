package sample.com.constructs;

import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.events.EventBus;
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
 * - EventBus (unicorns)
 * - EKS Pod Identity role (unicornstore-eks-pod-role)
 * - ECS Express Mode roles:
 *   - Infrastructure role (unicornstore-ecs-infrastructure-role)
 *   - Task execution role (unicornstore-ecs-task-execution-role)
 *   - Task role (unicornstore-ecs-task-role)
 * - Database schema setup (unicorns table)
 */
public class Unicorn extends Construct {

    // EventBus
    private EventBus eventBus;

    // EKS Roles
    private Role eksPodRole;

    // ECS Roles
    private Role ecsInfrastructureRole;
    private Role ecsTaskRole;
    private Role ecsTaskExecutionRole;

    // Database Setup
    private CustomResource databaseSetupResource;

    public Unicorn(final Construct scope, final String id, final UnicornProps props) {
        super(scope, id);

        // === EVENTBUS ===
        this.eventBus = EventBus.Builder.create(this, "UnicornEventBus")
            .eventBusName("unicorns")
            .build();

        // === EKS ROLES ===
        createEksRoles(props);

        // === ECS ROLES ===
        createEcsRoles(props);

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
     * - S3 bucket access
     * - Database secrets access
     * - EventBridge PutEvents
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

        // EventBridge access
        eventBus.grantPutEventsTo(eksPodRole);
    }

    /**
     * Creates ECS roles for Express Mode (Fargate):
     * - Infrastructure role: manages ALB, security groups, auto scaling
     * - Task execution role: pulls images, writes logs, injects secrets
     * - Task role: app runtime permissions (X-Ray, EventBridge)
     */
    private void createEcsRoles(UnicornProps props) {
        // === ECS Infrastructure Role (for Express Mode) ===
        ServicePrincipal ecsService = ServicePrincipal.Builder.create("ecs.amazonaws.com").build();

        this.ecsInfrastructureRole = Role.Builder.create(this, "UnicornStoreEcsInfrastructureRole")
            .roleName("unicornstore-ecs-infrastructure-role")
            .path("/service-role/")
            .assumedBy(ecsService)
            .description("ECS infrastructure role for Express Mode services")
            .build();

        ecsInfrastructureRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName(
            "service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"));

        // === ECS Task Execution Role ===
        ServicePrincipal ecsTasks = ServicePrincipal.Builder.create("ecs-tasks.amazonaws.com").build();

        this.ecsTaskExecutionRole = Role.Builder.create(this, "UnicornStoreEcsTaskExecutionRole")
            .roleName("unicornstore-ecs-task-execution-role")
            .path("/service-role/")
            .assumedBy(ecsTasks)
            .description("ECS task execution role for pulling images and injecting secrets")
            .build();

        // Base permissions: ECR pull + CloudWatch logs
        ecsTaskExecutionRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName(
            "service-role/AmazonECSTaskExecutionRolePolicy"));

        // Allow creating log groups (not in managed policy)
        ecsTaskExecutionRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("logs:CreateLogGroup"))
            .resources(List.of("*"))
            .build());

        // Database secrets injection at container startup (scoped)
        if (props.getDatabase() != null) {
            props.getDatabase().getDatabaseSecret().grantRead(ecsTaskExecutionRole);
            props.getDatabase().getParamDBConnectionString().grantRead(ecsTaskExecutionRole);
        }

        // === ECS Task Role (app runtime permissions) ===
        this.ecsTaskRole = Role.Builder.create(this, "UnicornStoreEcsTaskRole")
            .roleName("unicornstore-ecs-task-role")
            .path("/service-role/")
            .assumedBy(ecsTasks)
            .description("ECS task role for application runtime permissions")
            .build();

        // CloudWatch Agent and X-Ray for observability
        ecsTaskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy"));
        ecsTaskRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AWSXrayWriteOnlyAccess"));

        // EventBridge access
        eventBus.grantPutEventsTo(ecsTaskRole);
    }

    // Getters
    public EventBus getEventBus() {
        return eventBus;
    }

    public Role getEksPodRole() {
        return eksPodRole;
    }

    public Role getEcsInfrastructureRole() {
        return ecsInfrastructureRole;
    }

    public Role getEcsTaskRole() {
        return ecsTaskRole;
    }

    public Role getEcsTaskExecutionRole() {
        return ecsTaskExecutionRole;
    }

    // Props class
    public static class UnicornProps {
        private final Database database;
        private final IBucket workshopBucket;
        private final software.amazon.awscdk.services.ec2.IVpc vpc;

        private UnicornProps(Builder builder) {
            this.database = builder.database;
            this.workshopBucket = builder.workshopBucket;
            this.vpc = builder.vpc;
        }

        public static Builder builder() {
            return new Builder();
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
            private Database database;
            private IBucket workshopBucket;
            private software.amazon.awscdk.services.ec2.IVpc vpc;

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
