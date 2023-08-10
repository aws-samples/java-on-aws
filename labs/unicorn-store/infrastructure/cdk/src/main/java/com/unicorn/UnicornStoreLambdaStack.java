package com.unicorn;

import com.unicorn.core.InfrastructureStack;
import software.amazon.awscdk.*;
import software.amazon.awscdk.services.apigateway.LambdaRestApi;
import software.amazon.awscdk.services.apigateway.RestApi;
import software.amazon.awscdk.services.lambda.Alias;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.s3.BlockPublicAccess;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class UnicornStoreLambdaStack extends Stack {

    private final InfrastructureStack infrastructureStack;

    public UnicornStoreLambdaStack(final Construct scope, final String id, final StackProps props,
                                   final InfrastructureStack infrastructureStack) {
        super(scope, id, props);

        //Get previously created infrastructure stack
        this.infrastructureStack = infrastructureStack;
        var eventBridge = infrastructureStack.getEventBridge();

        //Create Spring Lambda function
        var unicornStoreSpringLambda = createUnicornLambdaFunction();

        //Permission for Spring Boot Lambda Function
        eventBridge.grantPutEventsTo(unicornStoreSpringLambda);

        var alias = Alias.Builder.create(this, "MyLambdaAlias")
                .aliasName("unicorn-alias")
                .version(unicornStoreSpringLambda.getLatestVersion())
                .build();
        //Setup a Proxy-Rest API to access the Spring Lambda function
        var restApi = setupRestApi(alias);

        var lambdaCodeBucket = Bucket.Builder
                .create(this, "LambdaCodeBucket")
                .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
                .enforceSsl(true)
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
                .runtime(Runtime.JAVA_17)
                .functionName("unicorn-store-spring")
                .memorySize(2048)
                .timeout(Duration.seconds(29))
                //Code is placeholder and will be overwritten in the lab
                .code(Code.fromAsset("../../software/unicorn-store-spring/src"))
                .handler("com.unicorn.store.StreamLambdaHandler::handleRequest")
                .vpc(infrastructureStack.getVpc())
                .securityGroups(List.of(infrastructureStack.getApplicationSecurityGroup()))
                .environment(Map.of(
                    "SPRING_DATASOURCE_PASSWORD", infrastructureStack.getDatabaseSecretString(),
                    "SPRING_DATASOURCE_URL", infrastructureStack.getDatabaseJDBCConnectionString(),
                    "SPRING_DATASOURCE_HIKARI_maximumPoolSize", "1",
                    "AWS_SERVERLESS_JAVA_CONTAINER_INIT_GRACE_TIME", "500",
                        "JAVA_TOOL_OPTIONS", "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
                ))
                .build();
    }
}
