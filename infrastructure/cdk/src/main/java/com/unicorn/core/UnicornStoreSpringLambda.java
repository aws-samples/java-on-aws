package com.unicorn.core;

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

import java.util.List;
import java.util.Map;

public class UnicornStoreSpringLambda extends Construct {

    private final InfrastructureCore infrastructureCore;
    private final StringParameter paramBucketName;
    private final Bucket lambdaCodeBucket;

    public UnicornStoreSpringLambda(final Construct scope, final String id,
        final InfrastructureCore infrastructureCore) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureCore = infrastructureCore;

        // Create Spring Lambda function
        var unicornStoreSpringLambda = createUnicornLambdaFunction();

        // Permission for Spring Boot Lambda Function
        infrastructureCore.getEventBridge().grantPutEventsTo(unicornStoreSpringLambda);

        var alias = Alias.Builder.create(this, "UnicornStoreSpringLambdaAlias")
            .aliasName("unicorn-store-spring-alias")
            .version(unicornStoreSpringLambda.getLatestVersion())
            .build();
        // Setup a Proxy-Rest API to access the Spring Lambda function
        setupRestApi(alias);

        lambdaCodeBucket = Bucket.Builder
            .create(this, "LambdaCodeBucket")
            .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
            .enforceSsl(true)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();
        paramBucketName = createParamBucketName();
    }

    private StringParameter createParamBucketName() {
        return StringParameter.Builder.create(this, "SsmParameterUnicornStoreBucketName")
            .allowedPattern(".*")
            .description("Unicorn Store Lambda code bucket name")
            .parameterName("unicornstore-lambda-bucket-name")
            .stringValue(lambdaCodeBucket.getBucketName())
            .tier(ParameterTier.STANDARD)
            .build();
    }

    public StringParameter getParamBucketName() {
        return paramBucketName;
    }

    private RestApi setupRestApi(Alias unicornStoreSpringLambdaAlias) {
        var restApi = LambdaRestApi.Builder.create(this, "UnicornStoreSpringApi")
            .restApiName("unicorn-store-spring-api")
            .handler(unicornStoreSpringLambdaAlias)
            // .endpointExportName("ApiEndpointSpring")
            .build();
        restApi.getNode().tryRemoveChild("Endpoint");
        return restApi;
    }

    private Function createUnicornLambdaFunction() {
        return Function.Builder.create(this, "UnicornStoreSpringFunction")
            // .runtime(Runtime.JAVA_21)
            // Runtime is placeholder and will be overwritten in the lab
            .runtime(Runtime.PYTHON_3_13)
            .functionName("unicorn-store-spring")
            .memorySize(2048)
            .timeout(Duration.seconds(29))
            // Code is placeholder and will be overwritten in the lab
            .code(Code.fromInline("def handler(event, context):\n    return 'placeholder'"))
            // .code(Code.fromAsset("../../labs/unicorn-store/software/unicorn-store-spring/src"))
            .handler("com.unicorn.store.StreamLambdaHandler::handleRequest")
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
