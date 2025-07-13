package com.unicorn.constructs;

import software.amazon.awscdk.services.apigateway.LambdaRestApi;
import software.amazon.awscdk.services.apigateway.RestApi;
import software.amazon.awscdk.services.lambda.Alias;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.s3.BlockPublicAccess;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.ssm.ParameterTier;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Duration;
import software.constructs.Construct;

import com.unicorn.core.InfrastructureCore;

import java.util.List;
import java.util.Map;

public class WorkshopFunction extends Construct {

    private final InfrastructureCore infrastructureCore;
    private final StringParameter paramBucketName;
    private final Bucket lambdaCodeBucket;
    private final String functionName;

    public WorkshopFunction(final Construct scope, final String id,
        final InfrastructureCore infrastructureCore, final String functionName) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureCore = infrastructureCore;
        this.functionName = functionName;

        // Create Spring Lambda function
        var lambda = createLambdaFunction();

        // Permission for Spring Boot Lambda Function
        infrastructureCore.getEventBridge().grantPutEventsTo(lambda);

        var alias = Alias.Builder.create(this, functionName + "-alias")
            .aliasName(functionName + "-alias")
            .version(lambda.getLatestVersion())
            .build();
        // Setup a Proxy-Rest API to access the Spring Lambda function
        setupRestApi(alias);

        lambdaCodeBucket = Bucket.Builder
            .create(this, functionName + "LambdaCodeBucket-")
            .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
            .enforceSsl(true)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();
        paramBucketName = createParamBucketName();
    }

    private StringParameter createParamBucketName() {
        return StringParameter.Builder.create(this, functionName + "-SsmParameterBucketName")
            .allowedPattern(".*")
            .description("Lambda code bucket name")
            .parameterName(functionName + "-lambda-code-bucket-name")
            .stringValue(lambdaCodeBucket.getBucketName())
            .tier(ParameterTier.STANDARD)
            .build();
    }

    public StringParameter getParamBucketName() {
        return paramBucketName;
    }

    private RestApi setupRestApi(Alias alias) {
        var restApi = LambdaRestApi.Builder.create(this, functionName + "-RestApi")
            .restApiName(functionName + "-rest-api")
            .handler(alias)
            .build();
        restApi.getNode().tryRemoveChild("Endpoint");
        return restApi;
    }

    private Function createLambdaFunction() {
        return Function.Builder.create(this, functionName + "-LambdaFunction")
            // Runtime is placeholder and will be overwritten in the lab
            .runtime(Runtime.PYTHON_3_13)
            .functionName(functionName)
            .memorySize(2048)
            .timeout(Duration.seconds(29))
            // Code is placeholder and will be overwritten in the lab
            .code(Code.fromInline("def handler(event, context):\n    return 'placeholder'"))
            // Handler is placeholder and will be overwritten in the lab
            .handler("com.example.StreamLambdaHandler::handleRequest")
            .vpc(infrastructureCore.getVpc())
            .securityGroups(List.of(infrastructureCore.getApplicationSecurityGroup()))
            .environment(Map.of(
                "SPRING_DATASOURCE_PASSWORD", infrastructureCore.getDatabaseSecretString(),
                "SPRING_DATASOURCE_URL", infrastructureCore.getDBConnectionString(),
                "SPRING_DATASOURCE_HIKARI_maximumPoolSize", "1",
                "AWS_SERVERLESS_JAVA_CONTAINER_INIT_GRACE_TIME", "500",
                    "JAVA_TOOL_OPTIONS", "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
            ))
            .build();
    }
}
