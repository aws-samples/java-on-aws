package com.unicorn.core;

import com.unicorn.constructs.EksCluster;
import software.amazon.awscdk.*;
import software.amazon.awscdk.services.apigateway.*;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;
import java.util.Objects;

public class InfrastructureMonitoringJVM extends Construct {

    public InfrastructureMonitoringJVM(Construct scope, String id, Bucket s3Bucket, EksCluster eksCluster, IVpc vpc) {
        super(scope, id);

        // Create Lambda function
        createThreadDumpLambda(s3Bucket, eksCluster, vpc);
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

        // // Allow Lambda to reach EKS cluster
        // lambdaSg.addEgressRule(
        //         Peer.securityGroupId(clusterSG.getSecurityGroupId()),
        //         Port.tcp(443),
        //         "Allow Lambda to reach Kubernetes API"
        // );

        // Allow EKS cluster to respond back to Lambda
        clusterSG.addIngressRule(
                Peer.securityGroupId(lambdaSg.getSecurityGroupId()),
                Port.tcp(443),
                "Allow Lambda access to Kubernetes API"
        );

        // Create separate security group for VPC endpoint
        SecurityGroup vpcEndpointSg = SecurityGroup.Builder.create(this, "VpcEndpointSecurityGroup")
                .vpc(vpc)
                .securityGroupName("unicornstore-apigw-vpce-sg")
                .description("Security group for API Gateway VPC endpoint")
                .allowAllOutbound(true)
                .build();

        // Allow VPC traffic to access API Gateway via VPC endpoint
        vpcEndpointSg.addIngressRule(
                Peer.ipv4(vpc.getVpcCidrBlock()),
                Port.tcp(443),
                "Allow VPC traffic to API Gateway VPC endpoint"
        );

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

        // Add permissions for Bedrock Models
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

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "aws-marketplace:Subscribe",
                "aws-marketplace:ViewSubscriptions"
            ))
            .resources(List.of(
                "*"
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

        // Create VPC endpoint for API Gateway
        InterfaceVpcEndpoint apiGatewayVpcEndpoint = InterfaceVpcEndpoint.Builder.create(this, "ApiGatewayVpcEndpoint")
                .vpc(vpc)
                .service(InterfaceVpcEndpointAwsService.APIGATEWAY)
                .subnets(SubnetSelection.builder()
                        .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                        .build())
                .privateDnsEnabled(true)
                .securityGroups(List.of(lambdaSg))
                .build();

        // Create private API Gateway
        RestApi api = RestApi.Builder.create(this, "ThreadDumpApi")
                .restApiName("unicornstore-thread-dump-api")
                .endpointConfiguration(EndpointConfiguration.builder()
                        .types(List.of(EndpointType.PRIVATE))
                        .vpcEndpoints(List.of(apiGatewayVpcEndpoint))
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
                                                        "aws:SourceVpce", apiGatewayVpcEndpoint.getVpcEndpointId()
                                                )
                                        ))
                                        .build()
                        ))
                        .build())
                .build();

        // Add Lambda integration
        LambdaIntegration integration = new LambdaIntegration(threadDumpFunction);
        api.getRoot().addMethod("POST", integration);
        api.getRoot().addProxy();

        if (eksCluster != null) {
            eksCluster.createAccessEntry(lambdaRole.getRoleArn(), eksCluster.getCluster().getName(), "lambda-eks-access-role");
        }

        return threadDumpFunction;
    }
}
