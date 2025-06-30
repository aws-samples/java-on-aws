package com.unicorn.core;

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

import java.util.List;
import java.util.Map;

public class InfrastructureLambdaBedrock extends Construct {

    private final Function threadDumpFunction;

    public InfrastructureLambdaBedrock(Construct scope, String id, String region, Bucket s3Bucket) {
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
                .description("Role for Lambda to access Bedrock")
                .managedPolicies(List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
                ))
                .build();

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
                        "bedrock:InvokeModel", "bedrock:ListFoundationModels",
                        "eks:DescribeCluster", "s3:PutObject", "sns:Publish"
                ))
                .resources(List.of(
                        "arn:aws:logs:*:*:*",
                        "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-3-7-sonnet-20250219-v1:0",
                        "arn:aws:eks:*:*:cluster/*",
                        String.format("arn:aws:s3:::%s/*", s3Bucket.getBucketName()),
                        "arn:aws:sns:*:*:*",
                        "arn:aws:bedrock:*:*:foundation-model/*"
                ))
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
                        "EKS_CLUSTER_NAME", "unicorn-store",
                        "K8S_NAMESPACE", "unicorn-store-spring",
                        "S3_BUCKET_NAME", s3Bucket.getBucketName()
                ))
                .build();

        s3Bucket.grantWrite(this.threadDumpFunction);

        LogGroup.Builder.create(this, "ThreadDumpLogGroup")
                .logGroupName("/aws/lambda/unicornstore-thread-dump-lambda")
                .retention(RetentionDays.ONE_WEEK) // Customize retention as needed
                .removalPolicy(RemovalPolicy.DESTROY)
                .build();

        // Create Function URL for Grafana webhook integration
        FunctionUrl functionUrl = FunctionUrl.Builder.create(this, "ThreadDumpFunctionUrl")
                .function(this.threadDumpFunction)
                .authType(FunctionUrlAuthType.NONE) // For simplicity; consider using AWS_IAM for production
                .build();

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
