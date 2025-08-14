package com.unicorn.core;

import com.unicorn.constructs.EksCluster;
import software.amazon.awscdk.*;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.sns.Topic;
import software.amazon.awscdk.services.sns.TopicPolicy;
import software.amazon.awscdk.services.sns.subscriptions.LambdaSubscription;
import software.amazon.awscdk.services.eks.CfnCluster;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;
import java.util.Objects;

public class InfrastructureMonitoringJVM extends Construct {

    public InfrastructureMonitoringJVM(Construct scope, String id, Bucket s3Bucket, EksCluster eksCluster, IVpc vpc) {
        super(scope, id);

        // Create Lambda function first (from InfrastructureLambdaBedrock)
        Function threadDumpFunction = createThreadDumpLambda(s3Bucket, eksCluster, vpc);

        // Create monitoring infrastructure (from MonitoringConstruct)
        createMonitoringInfrastructure(vpc, eksCluster.getCluster(), threadDumpFunction);
    }

    private Function createThreadDumpLambda(Bucket s3Bucket, EksCluster eksCluster, IVpc vpc) {
        // Create a security group for the Lambda function
        SecurityGroup lambdaSg = SecurityGroup.Builder.create(this, "LambdaSecurityGroup")
                .vpc(vpc)
                .securityGroupName("unicornstore-thread-dump-lambda-sg")
                .description("Security group for Thread Dump Lambda function")
                .allowAllOutbound(true)
                .build();

        ISecurityGroup clusterSG = eksCluster.getClusterSecurityGroup();

        // Allow Lambda to communicate with EKS API server
        clusterSG.addIngressRule(
                Peer.securityGroupId(lambdaSg.getSecurityGroupId()),
                Port.tcp(443),
                "Allow Lambda access to Kubernetes API"
        );

        // Allow Lambda to reach EKS cluster
        lambdaSg.addEgressRule(
                Peer.securityGroupId(clusterSG.getSecurityGroupId()),
                Port.tcp(443),
                "Allow Lambda to reach Kubernetes API"
        );

        // Allow EKS cluster to respond back to Lambda
        clusterSG.addIngressRule(
                Peer.securityGroupId(lambdaSg.getSecurityGroupId()),
                Port.tcp(443),
                "Allow Lambda access to Kubernetes API"
        );

        // IAM Role for Bedrock
        Role bedrockRole = Role.Builder.create(this, "BedrockAccessRole")
                .assumedBy(new ServicePrincipal("bedrock.amazonaws.com"))
                .description("Role for Bedrock Claude 3.7 access")
                .build();

        bedrockRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("bedrock:InvokeModel", "bedrock:ListFoundationModels"))
                .resources(List.of("arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-3-7-sonnet-20250219-v1:0"))
                .build());

        // IAM Role for Lambda
        Role lambdaRole = Role.Builder.create(this, "LambdaBedrockRole")
                .assumedBy(new ServicePrincipal("lambda.amazonaws.com"))
                .roleName("lambda-eks-access-role")
                .description("Role for Lambda to access Bedrock and EKS")
                .managedPolicies(List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"),
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole")
                ))
                .build();

        // Add permissions for Bedrock, S3, and SNS
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "logs:CreateLogGroup",
                "logs:CreateLogStream", 
                "logs:PutLogEvents"
            ))
            .resources(List.of(
                String.format("arn:aws:logs:%s:%s:log-group:/aws/lambda/unicornstore-thread-dump-lambda*", 
                    Stack.of(this).getRegion(), 
                    Stack.of(this).getAccount())
            ))
            .build());

        // Add broader permissions for Bedrock
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ))
            .resources(List.of(
                "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-3-7-sonnet-20250219-v1:0"
            ))
            .build());

        // Add permissions for AWS Secrets Manager access (IDE password)
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret"
            ))
            .resources(List.of(
                    String.format("arn:aws:secretsmanager:%s:*:secret:unicornstore-ide-password-lambda*", Stack.of(this).getRegion())
            ))
            .build());

        // Thread dumps S3 permissions
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "s3:PutObject", "s3:GetObject", "s3:ListBucket"
                ))
                .resources(List.of(
                        String.format("arn:aws:s3:::%s/thread-dumps/*", s3Bucket.getBucketName()),
                        String.format("arn:aws:s3:::%s", s3Bucket.getBucketName())
                ))
                .build());

        // Add permissions for EKS API access
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

        // Lambda function definition
        Function threadDumpFunction = Function.Builder.create(this, "unicornstore-thread-dump-lambda-eks")
                .functionName("unicornstore-thread-dump-lambda")
                .runtime(software.amazon.awscdk.services.lambda.Runtime.PYTHON_3_13)
                .code(Code.fromInline(
                        "import json\n" +
                        "import logging\n" +
                        "\n" +
                        "logger = logging.getLogger()\n" +
                        "logger.setLevel(logging.INFO)\n" +
                        "\n" +
                        "def lambda_handler(event, context):\n" +
                        "    logger.info('Dummy Lambda function invoked')\n" +
                        "    logger.info(f'Event: {json.dumps(event)}')\n" +
                        "    \n" +
                        "    return {\n" +
                        "        'statusCode': 200,\n" +
                        "        'headers': {\n" +
                        "            'Content-Type': 'application/json',\n" +
                        "            'Access-Control-Allow-Origin': '*'\n" +
                        "        },\n" +
                        "        'body': json.dumps({\n" +
                        "            'message': 'Hello from dummy Lambda function!',\n" +
                        "            'timestamp': context.aws_request_id,\n" +
                        "            'function_name': context.function_name\n" +
                        "        })\n" +
                        "    }\n"
                ))
                .handler("index.lambda_handler")
                .role(lambdaRole)
                .timeout(Duration.minutes(5))
                .memorySize(512)
                .vpc(vpc)
                .vpcSubnets(SubnetSelection.builder()
                        .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                        .build())
                .securityGroups(List.of(lambdaSg))
                .environment(Map.of(
                        "APP_LABEL", "unicorn-store-spring",
                        "EKS_CLUSTER_NAME", Objects.requireNonNull(eksCluster.getCluster().getName()),
                        "K8S_NAMESPACE", "unicorn-store-spring",
                        "S3_BUCKET_NAME", s3Bucket.getBucketName(),
                        "S3_THREAD_DUMPS_PREFIX", "thread-dumps/",
                        "KUBERNETES_AUTH_TYPE", "aws"
                ))
                .build();

        s3Bucket.grantWrite(threadDumpFunction);
        s3Bucket.grantRead(threadDumpFunction);

        LogGroup.Builder.create(this, "ThreadDumpLogGroup")
                .logGroupName("/aws/lambda/unicornstore-thread-dump-lambda")
                .retention(RetentionDays.ONE_WEEK)
                .removalPolicy(RemovalPolicy.DESTROY)
                .build();

        FunctionUrl.Builder.create(this, "ThreadDumpFunctionUrl")
                .function(threadDumpFunction)
                .authType(FunctionUrlAuthType.NONE)
                .build();

        threadDumpFunction.addPermission("AllowPublicInvocation",
                software.amazon.awscdk.services.lambda.Permission.builder()
                        .principal(new AnyPrincipal())
                        .action("lambda:InvokeFunctionUrl")
                        .functionUrlAuthType(FunctionUrlAuthType.NONE)
                        .build());

        if (eksCluster != null) {
            eksCluster.createAccessEntry(lambdaRole.getRoleArn(), eksCluster.getCluster().getName(), "lambda-eks-access-role");
        }

        return threadDumpFunction;
    }

    private void createMonitoringInfrastructure(IVpc vpc, CfnCluster eksCluster, Function alertHandlerLambda) {
        Topic alarmTopic = Topic.Builder.create(this, "AlarmTopic")
                .topicName("UnicornStoreAlarms")
                .displayName("Unicorn Store Alarms")
                .build();

        TopicPolicy.Builder.create(this, "AlarmTopicPolicy")
                .topics(List.of(alarmTopic))
                .build()
                .getDocument()
                .addStatements(PolicyStatement.Builder.create()
                        .effect(Effect.DENY)
                        .actions(List.of("sns:Publish"))
                        .principals(List.of(new AnyPrincipal()))
                        .resources(List.of(alarmTopic.getTopicArn()))
                        .conditions(Map.of("Bool", Map.of("aws:SecureTransport", "false")))
                        .build());

        alarmTopic.addSubscription(new LambdaSubscription(alertHandlerLambda));
    }

}
