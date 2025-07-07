package com.unicorn.core;

import com.unicorn.constructs.EksCluster;
import software.amazon.awscdk.*;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.logs.LogGroup;
import software.amazon.awscdk.services.logs.RetentionDays;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.s3.assets.AssetOptions;
import software.constructs.Construct;
import software.amazon.awscdk.services.lambda.FunctionUrl;
import software.amazon.awscdk.services.lambda.FunctionUrlAuthType;

import java.util.List;
import java.util.Map;

public class InfrastructureLambdaBedrock extends Construct {

    private final Function threadDumpFunction;

    public InfrastructureLambdaBedrock(Construct scope, String id, String region, Bucket s3Bucket, EksCluster eksCluster, IVpc vpc) {
        super(scope, id);

        // Create a security group for the Lambda function
        SecurityGroup lambdaSg = SecurityGroup.Builder.create(this, "LambdaSecurityGroup")
                .vpc(vpc)
                .securityGroupName("unicornstore-thread-dump-lambda-sg")
                .description("Security group for Thread Dump Lambda function")
                .allowAllOutbound(true)
                .build();

        ISecurityGroup clusterSG = eksCluster.getClusterSecurityGroup();

        // Allow Lambda to communicate with EKS API server
        // The Kubernetes API typically runs on port 443 (HTTPS)
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
                .resources(List.of("arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-3-7-sonnet-20250219-v1:0"))
                .build());

        // IAM Role for Lambda
        // IAM Role for Lambda
        Role lambdaRole = Role.Builder.create(this, "LambdaBedrockRole")
                .assumedBy(new ServicePrincipal("lambda.amazonaws.com"))
                .description("Role for Lambda to access Bedrock and EKS")
                .managedPolicies(List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole"),
                        // Add VPC access policy
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole")
                ))
                .build();

        // Add permissions for Bedrock, S3, and SNS
        // Add permissions for Bedrock, S3, and SNS
        // Add permissions for logs
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                ))
                .resources(List.of("arn:aws:logs:*:*:*"))
                .build());

        // Add broader permissions for Bedrock
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "bedrock:InvokeModel",
                        "bedrock:InvokeModelWithResponseStream",
                        "bedrock:ListFoundationModels"
                ))
                .resources(List.of("*"))  // Grant access to all Bedrock resources
                .build());

        // Add separate policy for S3 and SNS
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "s3:PutObject", "s3:GetObject", "s3:ListBucket",
                        "sns:Publish"
                ))
                .resources(List.of(
                        String.format("arn:aws:s3:::%s/*", s3Bucket.getBucketName()),
                        String.format("arn:aws:s3:::%s", s3Bucket.getBucketName()),
                        "arn:aws:sns:*:*:*"
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

        // Docker bundling config for Lambda
        BundlingOptions bundlingOptions = BundlingOptions.builder()
                .image(DockerImage.fromRegistry("public.ecr.aws/sam/build-python3.13:latest"))
                .command(List.of(
                        "bash", "-c", "chmod +x build.sh && ./build.sh"
                ))
                .user("root")
                .outputType(BundlingOutput.ARCHIVED)
                .build();

        // Lambda function definition
        this.threadDumpFunction = Function.Builder.create(this, "unicornstore-thread-dump-lambda-eks")
                .functionName("unicornstore-thread-dump-lambda")
                .runtime(Runtime.PYTHON_3_13)
                .code(Code.fromAsset("../lambda", AssetOptions.builder()
                        .bundling(bundlingOptions)
                        .build()))
                .handler("lambda_function.lambda_handler")
                .role(lambdaRole)
                .timeout(Duration.minutes(5))
                .memorySize(512)
                // Add VPC configuration - use private subnets with NAT
                .vpc(vpc)
                .vpcSubnets(SubnetSelection.builder()
                        .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                        .build())
                .securityGroups(List.of(lambdaSg))
                .environment(Map.of(
                        "APP_LABEL", "unicorn-store-spring",
                        "EKS_CLUSTER_NAME", eksCluster != null ? eksCluster.getCluster().getName() : "unicorn-store",
                        "K8S_NAMESPACE", "unicorn-store-spring",
                        "S3_BUCKET_NAME", s3Bucket.getBucketName(),
                        "KUBERNETES_AUTH_TYPE", "aws"  // Use AWS IAM authentication for EKS
                ))
                .build();


        s3Bucket.grantWrite(this.threadDumpFunction);
        s3Bucket.grantRead(this.threadDumpFunction);

        // Create Log Group with retention
        LogGroup.Builder.create(this, "ThreadDumpLogGroup")
                .logGroupName("/aws/lambda/unicornstore-thread-dump-lambda")
                .retention(RetentionDays.ONE_WEEK)
                .removalPolicy(RemovalPolicy.DESTROY)
                .build();

        // Create Function URL for Grafana webhook integration
        FunctionUrl functionUrl = FunctionUrl.Builder.create(this, "ThreadDumpFunctionUrl")
                .function(this.threadDumpFunction)
                .authType(FunctionUrlAuthType.NONE)
                .build();

        // Add resource-based policy to allow public access to Function URL
        this.threadDumpFunction.addPermission("AllowPublicInvocation",
                software.amazon.awscdk.services.lambda.Permission.builder()
                        .principal(new AnyPrincipal())
                        .action("lambda:InvokeFunctionUrl")
                        .functionUrlAuthType(FunctionUrlAuthType.NONE)
                        .build());

        // Use EKS Access Entries API instead of aws-auth ConfigMap
        if (eksCluster != null) {
            // Create an access entry for the Lambda role
            eksCluster.createAccessEntry(lambdaRole.getRoleArn(), eksCluster.getCluster().getName(), "lambda-eks-acces-role");
        }

        // Output the Function URL for reference
        CfnOutput.Builder.create(this, "ThreadDumpFunctionUrlOutput")
                .exportName("ThreadDumpFunctionUrl")
                .description("URL for invoking the Thread Dump Lambda function")
                .value(functionUrl.getUrl())
                .build();

        // Output the Lambda security group ID for reference
        CfnOutput.Builder.create(this, "LambdaSecurityGroupOutput")
                .exportName("LambdaSecurityGroupId")
                .description("Security Group ID for the Lambda function")
                .value(lambdaSg.getSecurityGroupId())
                .build();

    }

    public Function getThreadDumpFunction() {
        return threadDumpFunction;
    }
}