package com.unicorn.core;

import com.unicorn.constructs.EksCluster;
import software.amazon.awscdk.*;
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
import software.amazon.awscdk.services.eks.AccessEntry;
import software.amazon.awscdk.services.eks.AccessPolicy;

import java.util.List;
import java.util.Map;

public class InfrastructureLambdaBedrock extends Construct {

    private final Function threadDumpFunction;

    public InfrastructureLambdaBedrock(Construct scope, String id, String region, Bucket s3Bucket, EksCluster eksCluster) {
        super(scope, id);

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
        Role lambdaRole = Role.Builder.create(this, "LambdaBedrockRole")
                .assumedBy(new ServicePrincipal("lambda.amazonaws.com"))
                .description("Role for Lambda to access Bedrock and EKS")
                .managedPolicies(List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
                ))
                .build();

        // Add permissions for Bedrock, S3, and SNS
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
                        "bedrock:InvokeModel", "bedrock:ListFoundationModels",
                        "s3:PutObject", "s3:GetObject", "s3:ListBucket",
                        "sns:Publish"
                ))
                .resources(List.of(
                        "arn:aws:logs:*:*:*",
                        "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-3-7-sonnet-20250219-v1:0",
                        String.format("arn:aws:s3:::%s/*", s3Bucket.getBucketName()),
                        String.format("arn:aws:s3:::%s", s3Bucket.getBucketName()),
                        "arn:aws:sns:*:*:*",
                        "arn:aws:bedrock:*:*:foundation-model/*"
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
                .description("URL for invoking the Thread Dump Lambda function")
                .value(functionUrl.getUrl())
                .build();
    }

    public Function getThreadDumpFunction() {
        return threadDumpFunction;
    }
}