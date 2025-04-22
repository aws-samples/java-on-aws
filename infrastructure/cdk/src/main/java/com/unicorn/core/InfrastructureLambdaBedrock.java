package com.unicorn.core;

import software.amazon.awscdk.BundlingOptions;
import software.amazon.awscdk.DockerImage;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.s3.assets.AssetOptions;
import software.constructs.Construct;

import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

public class InfrastructureLambdaBedrock extends Construct {

    private Function threadDumpFunction;

    public InfrastructureLambdaBedrock(Construct scope, String id, String region, String s3Bucket) {
        super(scope, id);
        
        // Create IAM Role for Bedrock access
        Role bedrockRole = Role.Builder.create(this, "BedrockAccessRole")
                .assumedBy(new ServicePrincipal("bedrock.amazonaws.com"))
                .description("Role for Bedrock Claude 3.7 access")
                .build();

        // Add Bedrock policy
        bedrockRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "bedrock:InvokeModel",
                        "bedrock:ListFoundationModels"
                ))
                .resources(List.of(
                        // ARN for Claude 3.7 Sonnet model
                        "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-3-7-sonnet-20250219-v1:0"
                ))
                .build());

        // Create IAM Role for Lambda to access Bedrock
        Role lambdaRole = Role.Builder.create(this, "LambdaBedrockRole")
                .assumedBy(new ServicePrincipal("lambda.amazonaws.com"))
                .description("Role for Lambda to access Bedrock")
                .build();

        // Add Lambda basic execution role
        lambdaRole.addManagedPolicy(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
        );

        // Add CloudWatch Logs permissions
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                ))
                .resources(List.of("arn:aws:logs:*:*:*"))
                .build());

        // Add Bedrock permissions to Lambda role
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "bedrock:InvokeModel",
                        "bedrock:ListFoundationModels"
                ))
                .resources(List.of(
                        "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-3-7-sonnet-20250219-v1:0"
                ))
                .build());

        // Add permissions for EKS, S3, SNS, and Bedrock
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "eks:DescribeCluster",
                        "s3:PutObject",
                        "sns:Publish"
                ))
                .resources(List.of(
                        "arn:aws:eks:*:*:cluster/*",
                        String.format("arn:aws:s3:::%s/*", s3Bucket),
                        "arn:aws:sns:*:*:*",
                        "arn:aws:bedrock:*:*:foundation-model/*"
                ))
                .build());

        // Define the path to the Lambda function source
        String lambdaPath = Paths.get(System.getProperty("user.dir"), "..", "lambda").toString();

        // Create Lambda function using custom build script
        threadDumpFunction = Function.Builder.create(this, "PythonLambda")
                .runtime(Runtime.PYTHON_3_13)
                .code(Code.fromAsset(lambdaPath, AssetOptions.builder()
                        .bundling(BundlingOptions.builder()
                                .image(DockerImage.fromRegistry("public.ecr.aws/sam/build-python3.13"))
                                .command(Arrays.asList(
                                        "bash", "-c",
                                        // Execute build script and copy output
                                        "cd /asset-input && " +
                                                "chmod +x build.sh && " +
                                                "./build.sh && " +
                                                "cp -r dist/* /asset-output/"
                                ))
                                .build())
                        .build()))
                .handler("lambda_function.lambda_handler")
                .memorySize(512)
                .timeout(Duration.minutes(5))
                .role(lambdaRole)
                .environment(Map.of(
                        "APP_LABEL", "unicorn-store-spring",
                        "EKS_CLUSTER_NAME", "unicorn-store",
                        "K8S_NAMESPACE", "unicorn-store-spring",
                        "S3_BUCKET_NAME", s3Bucket
                ))
                .build();
    }

    public Function getThreadDumpFunction() {
        return threadDumpFunction;
    }
}
