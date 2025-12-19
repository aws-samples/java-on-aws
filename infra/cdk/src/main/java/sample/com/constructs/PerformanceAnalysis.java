package sample.com.constructs;

import software.amazon.awscdk.Aws;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.apigateway.*;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.eks.v2.alpha.AccessEntry;
import software.amazon.awscdk.services.eks.v2.alpha.AccessEntryType;
import software.amazon.awscdk.services.eks.v2.alpha.AccessPolicy;
import software.amazon.awscdk.services.eks.v2.alpha.AccessPolicyNameOptions;
import software.amazon.awscdk.services.eks.v2.alpha.AccessScopeType;
import software.amazon.awscdk.services.eks.v2.alpha.Cluster;
import software.amazon.awscdk.services.eks.v2.alpha.IAccessPolicy;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.s3.BlockPublicAccess;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

/**
 * PerformanceAnalysis construct for Java Performance Analysis and Optimization.
 *
 * Provides AI-powered diagnostics for modern Java applications including:
 * - Thread dump analysis via Lambda + API Gateway
 * - Profiling analysis via async-profiler + jvm-analysis-service
 *
 * Both ThreadAnalysis and ProfilingAnalysis are enabled by default.
 */
public class PerformanceAnalysis extends Construct {

    private final Bucket workshopBucket;
    private final StringParameter bucketNameParameter;
    private final Role lambdaBedrockRole;
    private SecurityGroup lambdaSecurityGroup;
    private Function threadDumpLambda;
    private RestApi threadDumpApi;
    private Role jvmAnalysisServiceRole;
    private Repository jvmAnalysisEcr;

    public PerformanceAnalysis(final Construct scope, final String id, final PerformanceAnalysisProps props) {
        super(scope, id);

        // === SHARED RESOURCES ===

        // Create S3 bucket for workshop data (thread dumps, profiling data)
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"));
        this.workshopBucket = Bucket.Builder.create(this, "Bucket")
            .bucketName(String.format("workshop-%s-%s-%s", Aws.ACCOUNT_ID, Aws.REGION, timestamp))
            .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Create SSM parameter for bucket name discovery
        this.bucketNameParameter = StringParameter.Builder.create(this, "BucketNameParameter")
            .parameterName("workshop-analysis-bucket-name")
            .description("Workshop analysis bucket name for thread dumps and profiling data")
            .stringValue(workshopBucket.getBucketName())
            .build();

        // Create Lambda Bedrock role with EKS and ECS access
        this.lambdaBedrockRole = Role.Builder.create(this, "LambdaBedrockRole")
            .roleName("workshop-analysis-lambda-role")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .description("Role for Lambda to access Bedrock, EKS, and ECS for performance analysis")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"),
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole")
            ))
            .build();

        // Add Bedrock permissions
        lambdaBedrockRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ))
            .resources(List.of(
                "arn:aws:bedrock:*:*:inference-profile/global.anthropic.claude-sonnet-4-20250514-v1:0",
                "arn:aws:bedrock:*:*:foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
            ))
            .build());

        // Add Secrets Manager permission for IDE password (webhook auth)
        lambdaBedrockRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("secretsmanager:GetSecretValue"))
            .resources(List.of("arn:aws:secretsmanager:*:*:secret:workshop-ide-password*"))
            .build());

        // Add EKS access permissions
        lambdaBedrockRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "eks:DescribeCluster",
                "eks:AccessKubernetesApi",
                "eks:ListClusters",
                "sts:GetCallerIdentity"
            ))
            .resources(List.of("*"))
            .build());

        // Add ECS access permissions
        lambdaBedrockRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "ecs:DescribeClusters",
                "ecs:DescribeServices",
                "ecs:DescribeTasks",
                "ecs:ListTasks",
                "ecs:ExecuteCommand"
            ))
            .resources(List.of("*"))
            .build());

        // Add S3 permissions for thread dumps and profiling data
        workshopBucket.grantReadWrite(lambdaBedrockRole);

        // === THREAD ANALYSIS ===
        if (props.isThreadAnalysisEnabled()) {
            createThreadAnalysis(props);
        }

        // === PROFILING ANALYSIS ===
        if (props.isProfilingAnalysisEnabled()) {
            createProfilingAnalysis(props);
        }
    }


    private void createThreadAnalysis(PerformanceAnalysisProps props) {
        // Create Lambda security group
        this.lambdaSecurityGroup = SecurityGroup.Builder.create(this, "LambdaSecurityGroup")
            .vpc(props.getVpc())
            .securityGroupName("workshop-analysis-lambda-sg")
            .description("Security group for Thread Dump Lambda function")
            .allowAllOutbound(true)
            .build();

        // Allow inbound from VPC for HTTPS
        lambdaSecurityGroup.addIngressRule(
            Peer.ipv4(props.getVpc().getVpcCidrBlock()),
            Port.tcp(443),
            "Allow VPC traffic to Lambda"
        );

        // Create CloudWatch Log Group (referenced by Lambda function)
        LogGroup.Builder.create(this, "ThreadDumpLogGroup")
            .logGroupName("/aws/lambda/workshop-thread-dump-lambda")
            .retention(RetentionDays.ONE_WEEK)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Create Thread Dump Lambda function
        this.threadDumpLambda = Function.Builder.create(this, "ThreadDumpLambda")
            .functionName("workshop-thread-dump-lambda")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.lambda_handler")
            .code(Code.fromInline(loadFile("/lambda/thread-dump-lambda.py")))
            .role(lambdaBedrockRole)
            .timeout(Duration.minutes(5))
            .memorySize(512)
            .vpc(props.getVpc())
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .securityGroups(List.of(lambdaSecurityGroup))
            .environment(Map.of(
                "S3_BUCKET_NAME", workshopBucket.getBucketName(),
                "EKS_CLUSTER_NAME", props.getEksClusterName() != null ? props.getEksClusterName() : "workshop-eks",
                "S3_THREAD_DUMPS_PREFIX", "thread-dumps/",
                "APP_LABEL", "unicorn-store-spring",
                "KUBERNETES_AUTH_TYPE", "aws",
                "K8S_NAMESPACE", "unicorn-store-spring",
                "SECRET_NAME", "workshop-ide-password"
            ))
            .build();

        // Create VPC Endpoint for API Gateway
        InterfaceVpcEndpoint apiGatewayEndpoint = InterfaceVpcEndpoint.Builder.create(this, "ApiGatewayVpcEndpoint")
            .vpc(props.getVpc())
            .service(InterfaceVpcEndpointAwsService.APIGATEWAY)
            .subnets(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .securityGroups(List.of(lambdaSecurityGroup))
            .privateDnsEnabled(true)
            .build();

        // Create Private REST API Gateway
        this.threadDumpApi = RestApi.Builder.create(this, "ThreadDumpApi")
            .restApiName("workshop-thread-dump-api")
            .endpointConfiguration(EndpointConfiguration.builder()
                .types(List.of(EndpointType.PRIVATE))
                .vpcEndpoints(List.of(apiGatewayEndpoint))
                .build())
            .policy(PolicyDocument.Builder.create()
                .statements(List.of(
                    PolicyStatement.Builder.create()
                        .effect(Effect.ALLOW)
                        .principals(List.of(new AnyPrincipal()))
                        .actions(List.of("execute-api:Invoke"))
                        .resources(List.of("*"))
                        .conditions(Map.of(
                            "StringEquals", Map.of(
                                "aws:SourceVpce", apiGatewayEndpoint.getVpcEndpointId()
                            )
                        ))
                        .build()
                ))
                .build())
            .build();

        // Remove auto-generated endpoint output
        threadDumpApi.getNode().tryRemoveChild("Endpoint");

        // Add POST method to root
        LambdaIntegration lambdaIntegration = LambdaIntegration.Builder.create(threadDumpLambda)
            .build();

        threadDumpApi.getRoot().addMethod("POST", lambdaIntegration);

        // Create EKS Access Entry for Lambda role (if EKS cluster provided)
        if (props.getEksCluster() != null) {
            IAccessPolicy clusterAdminPolicy = AccessPolicy.fromAccessPolicyName(
                "AmazonEKSClusterAdminPolicy",
                AccessPolicyNameOptions.builder()
                    .accessScopeType(AccessScopeType.CLUSTER)
                    .build()
            );

            AccessEntry.Builder.create(this, "LambdaAccessEntry")
                .cluster(props.getEksCluster())
                .principal(lambdaBedrockRole.getRoleArn())
                .accessEntryType(AccessEntryType.STANDARD)
                .accessPolicies(List.of(clusterAdminPolicy))
                .build();

            // Allow Lambda security group to access EKS cluster security group
            if (props.getEksCluster().getClusterSecurityGroup() != null) {
                props.getEksCluster().getClusterSecurityGroup().addIngressRule(
                    lambdaSecurityGroup,
                    Port.tcp(443),
                    "Allow Lambda access to Kubernetes API"
                );
            }
        }
    }

    private void createProfilingAnalysis(PerformanceAnalysisProps props) {
        // Create ECR repository for jvm-analysis-service
        this.jvmAnalysisEcr = Repository.Builder.create(this, "JvmAnalysisEcr")
            .repositoryName("jvm-analysis-service")
            .removalPolicy(RemovalPolicy.DESTROY)
            .emptyOnDelete(true)
            .build();

        // Create Pod Identity role for jvm-analysis-service
        // Pod Identity requires both sts:AssumeRole and sts:TagSession
        CompositePrincipal podIdentityPrincipal = new CompositePrincipal(
            ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()
        );

        this.jvmAnalysisServiceRole = Role.Builder.create(this, "JvmAnalysisServiceRole")
            .roleName("jvm-analysis-service-eks-pod-role")
            .assumedBy(podIdentityPrincipal)
            .description("Role for jvm-analysis-service EKS pod to access Bedrock and S3")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess")
            ))
            .build();

        // Add sts:TagSession to the assume role policy for Pod Identity
        PolicyDocument assumeRolePolicy = jvmAnalysisServiceRole.getAssumeRolePolicy();
        if (assumeRolePolicy != null) {
            assumeRolePolicy.addStatements(
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .principals(List.of(ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()))
                    .actions(List.of("sts:TagSession"))
                    .build()
            );
        }

        // Add S3 permissions for profiling data
        jvmAnalysisServiceRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject"
            ))
            .resources(List.of(
                workshopBucket.getBucketArn(),
                workshopBucket.getBucketArn() + "/*"
            ))
            .build());
    }

    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException | NullPointerException e) {
            // Return dummy Lambda code if file not found
            return """
                import json
                import logging

                logger = logging.getLogger()
                logger.setLevel(logging.INFO)

                def lambda_handler(event, context):
                    logger.info('Thread Dump Lambda function invoked')
                    logger.info(f'Event: {json.dumps(event)}')

                    return {
                        'statusCode': 200,
                        'headers': {
                            'Content-Type': 'application/json',
                            'Access-Control-Allow-Origin': '*'
                        },
                        'body': json.dumps({
                            'message': 'Thread dump analysis placeholder',
                            'timestamp': context.aws_request_id,
                            'function_name': context.function_name
                        })
                    }
                """;
        }
    }

    // Getters
    public Bucket getWorkshopBucket() {
        return workshopBucket;
    }

    public StringParameter getBucketNameParameter() {
        return bucketNameParameter;
    }

    public Role getLambdaBedrockRole() {
        return lambdaBedrockRole;
    }

    public SecurityGroup getLambdaSecurityGroup() {
        return lambdaSecurityGroup;
    }

    public Function getThreadDumpLambda() {
        return threadDumpLambda;
    }

    public RestApi getThreadDumpApi() {
        return threadDumpApi;
    }

    public Role getJvmAnalysisServiceRole() {
        return jvmAnalysisServiceRole;
    }

    public Repository getJvmAnalysisEcr() {
        return jvmAnalysisEcr;
    }


    // Props class
    public static class PerformanceAnalysisProps {
        private final IVpc vpc;
        private final Cluster eksCluster;
        private final String eksClusterName;
        private final boolean threadAnalysisEnabled;
        private final boolean profilingAnalysisEnabled;

        private PerformanceAnalysisProps(Builder builder) {
            this.vpc = builder.vpc;
            this.eksCluster = builder.eksCluster;
            this.eksClusterName = builder.eksClusterName;
            this.threadAnalysisEnabled = builder.threadAnalysisEnabled;
            this.profilingAnalysisEnabled = builder.profilingAnalysisEnabled;
        }

        public static Builder builder() {
            return new Builder();
        }

        public IVpc getVpc() {
            return vpc;
        }

        public Cluster getEksCluster() {
            return eksCluster;
        }

        public String getEksClusterName() {
            return eksClusterName;
        }

        public boolean isThreadAnalysisEnabled() {
            return threadAnalysisEnabled;
        }

        public boolean isProfilingAnalysisEnabled() {
            return profilingAnalysisEnabled;
        }

        public static class Builder {
            private IVpc vpc;
            private Cluster eksCluster;
            private String eksClusterName;
            private boolean threadAnalysisEnabled = true;  // Enabled by default
            private boolean profilingAnalysisEnabled = true;  // Enabled by default

            public Builder vpc(IVpc vpc) {
                this.vpc = vpc;
                return this;
            }

            public Builder eksCluster(Cluster eksCluster) {
                this.eksCluster = eksCluster;
                return this;
            }

            public Builder eksClusterName(String eksClusterName) {
                this.eksClusterName = eksClusterName;
                return this;
            }

            public Builder threadAnalysisEnabled(boolean threadAnalysisEnabled) {
                this.threadAnalysisEnabled = threadAnalysisEnabled;
                return this;
            }

            public Builder profilingAnalysisEnabled(boolean profilingAnalysisEnabled) {
                this.profilingAnalysisEnabled = profilingAnalysisEnabled;
                return this;
            }

            public PerformanceAnalysisProps build() {
                if (vpc == null) {
                    throw new IllegalArgumentException("VPC is required");
                }
                return new PerformanceAnalysisProps(this);
            }
        }
    }
}
