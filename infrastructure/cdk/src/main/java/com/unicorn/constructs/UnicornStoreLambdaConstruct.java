package com.unicorn;

import com.unicorn.core.InfrastructureConstruct;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnOutputProps;
// import software.amazon.awscdk.*;
import software.amazon.awscdk.services.apigateway.LambdaRestApi;
import software.amazon.awscdk.services.apigateway.RestApi;
import software.amazon.awscdk.services.lambda.Alias;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.s3.BlockPublicAccess;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.Duration;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class UnicornStoreLambdaConstruct extends Construct {

    private final InfrastructureConstruct infrastructureConstruct;

    public UnicornStoreLambdaConstruct(final Construct scope, final String id,
        final InfrastructureConstruct infrastructureConstruct) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureConstruct = infrastructureConstruct;
        var eventBridge = infrastructureConstruct.getEventBridge();

        //Create Spring Lambda function
        var unicornStoreSpringLambda = createUnicornLambdaFunction();

        //Permission for Spring Boot Lambda Function
        eventBridge.grantPutEventsTo(unicornStoreSpringLambda);

        var alias = Alias.Builder.create(this, "UnicornStoreSpringLambdaAlias")
                .aliasName("unicorn-alias")
                .version(unicornStoreSpringLambda.getLatestVersion())
                .build();
        //Setup a Proxy-Rest API to access the Spring Lambda function
        var restApi = setupRestApi(alias);

        var lambdaCodeBucket = Bucket.Builder
                .create(this, "LambdaCodeBucket")
                .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
                .enforceSsl(true)
                .removalPolicy(RemovalPolicy.DESTROY)
                .build();

        //Create output values for later reference
        new CfnOutput(this, "unicorn-store-spring-function-arn", CfnOutputProps.builder()
                .value(unicornStoreSpringLambda.getFunctionArn())
                .build());

        new CfnOutput(this, "ApiEndpointSpring", CfnOutputProps.builder()
                .value(restApi.getUrl())
                .build());

        new CfnOutput(this, "BucketLambdaCode", CfnOutputProps.builder()
                .value(lambdaCodeBucket.getBucketName())
                .build());
    }

    private RestApi setupRestApi(Alias unicornStoreSpringLambdaAlias) {
        return LambdaRestApi.Builder.create(this, "UnicornStoreSpringApi")
                .restApiName("UnicornStoreSpringApi")
                .handler(unicornStoreSpringLambdaAlias)
                .build();
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
                .vpc(infrastructureConstruct.getVpc())
                .securityGroups(List.of(infrastructureConstruct.getApplicationSecurityGroup()))
                .environment(Map.of(
                    "SPRING_DATASOURCE_PASSWORD", infrastructureConstruct.getDatabaseSecretString(),
                    "SPRING_DATASOURCE_URL", infrastructureConstruct.getDatabaseJDBCConnectionString(),
                    "SPRING_DATASOURCE_HIKARI_maximumPoolSize", "1",
                    "AWS_SERVERLESS_JAVA_CONTAINER_INIT_GRACE_TIME", "500",
                        "JAVA_TOOL_OPTIONS", "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
                ))
                .build();
    }
}
