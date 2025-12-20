package sample.com.constructs;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.apigateway.*;
import software.amazon.awscdk.services.ec2.*;
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
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * ThreadAnalysis construct for thread dump analysis.
 * Creates Lambda function and API Gateway for thread dump collection and AI analysis.
 */
public class ThreadAnalysis extends Construct {

    private final SecurityGroup lambdaSecurityGroup;
    private final Function threadDumpLambda;
    private final RestApi threadDumpApi;
    private final Role lambdaRole;

    public static class ThreadAnalysisProps {
        private String prefix = "workshop";
        private IVpc vpc;
        private Cluster eksCluster;
        private String eksClusterName;
        private Bucket workshopBucket;

        public static ThreadAnalysisProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private ThreadAnalysisProps props = new ThreadAnalysisProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public Builder vpc(IVpc vpc) { props.vpc = vpc; return this; }
            public Builder eksCluster(Cluster eksCluster) { props.eksCluster = eksCluster; return this; }
            public Builder eksClusterName(String eksClusterName) { props.eksClusterName = eksClusterName; return this; }
            public Builder workshopBucket(Bucket workshopBucket) { props.workshopBucket = workshopBucket; return this; }
            public ThreadAnalysisProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
        public IVpc getVpc() { return vpc; }
        public Cluster getEksCluster() { return eksCluster; }
        public String getEksClusterName() { return eksClusterName; }
        public Bucket getWorkshopBucket() { return workshopBucket; }
    }

    public ThreadAnalysis(final Construct scope, final String id, final ThreadAnalysisProps props) {
        super(scope, id);

        String prefix = props.getPrefix();

        // Create Lambda role with Bedrock, EKS, and ECS access
        this.lambdaRole = Role.Builder.create(this, "LambdaRole")
            .roleName(prefix + "-thread-dump-lambda-role")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .description("Role for Thread Dump Lambda to access Bedrock, EKS, and ECS")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"),
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole")
            ))
            .build();

        // Add Bedrock permissions
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
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
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("secretsmanager:GetSecretValue"))
            .resources(List.of("arn:aws:secretsmanager:*:*:secret:" + prefix + "-ide-password*"))
            .build());

        // Add EKS access permissions
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
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
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
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

        // Add S3 permissions for thread dumps
        if (props.getWorkshopBucket() != null) {
            props.getWorkshopBucket().grantReadWrite(lambdaRole);
        }

        // Create Lambda security group
        this.lambdaSecurityGroup = SecurityGroup.Builder.create(this, "SecurityGroup")
            .vpc(props.getVpc())
            .securityGroupName(prefix + "-thread-dump-lambda-sg")
            .description("Security group for Thread Dump Lambda function")
            .allowAllOutbound(true)
            .build();

        // Allow inbound from VPC for HTTPS
        lambdaSecurityGroup.addIngressRule(
            Peer.ipv4(props.getVpc().getVpcCidrBlock()),
            Port.tcp(443),
            "Allow VPC traffic to Lambda"
        );

        // Create CloudWatch Log Group
        LogGroup.Builder.create(this, "LogGroup")
            .logGroupName("/aws/lambda/" + prefix + "-thread-dump-lambda")
            .retention(RetentionDays.ONE_WEEK)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Create Thread Dump Lambda function
        String eksClusterName = props.getEksClusterName() != null ? props.getEksClusterName() : prefix + "-eks";
        String bucketName = props.getWorkshopBucket() != null ? props.getWorkshopBucket().getBucketName() : "";

        this.threadDumpLambda = Function.Builder.create(this, "Lambda")
            .functionName(prefix + "-thread-dump-lambda")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.lambda_handler")
            .code(Code.fromInline(loadFile("/lambda/thread-dump-lambda.py")))
            .role(lambdaRole)
            .timeout(Duration.minutes(5))
            .memorySize(512)
            .vpc(props.getVpc())
            .vpcSubnets(SubnetSelection.builder()
                .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                .build())
            .securityGroups(List.of(lambdaSecurityGroup))
            .environment(Map.of(
                "S3_BUCKET_NAME", bucketName,
                "EKS_CLUSTER_NAME", eksClusterName,
                "S3_THREAD_DUMPS_PREFIX", "thread-dumps/",
                "APP_LABEL", "unicorn-store-spring",
                "KUBERNETES_AUTH_TYPE", "aws",
                "K8S_NAMESPACE", "unicorn-store-spring",
                "SECRET_NAME", prefix + "-ide-password"
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
        this.threadDumpApi = RestApi.Builder.create(this, "Api")
            .restApiName(prefix + "-thread-dump-api")
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
                .principal(lambdaRole.getRoleArn())
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
    public SecurityGroup getLambdaSecurityGroup() {
        return lambdaSecurityGroup;
    }

    public Function getThreadDumpLambda() {
        return threadDumpLambda;
    }

    public RestApi getThreadDumpApi() {
        return threadDumpApi;
    }

    public Role getLambdaRole() {
        return lambdaRole;
    }
}
