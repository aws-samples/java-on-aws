package com.unicorn;

import com.unicorn.constructs.InfrastructureCore;
import com.unicorn.constructs.InfrastructureImmDay;
import com.unicorn.constructs.DatabaseSetup;
import com.unicorn.constructs.WorkshopIde;
import com.unicorn.constructs.EksCluster;
import com.unicorn.constructs.UnicornStoreLambda;
import software.amazon.awscdk.CfnParameter;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnOutputProps;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.apigateway.LambdaRestApi;
import software.amazon.awscdk.services.apigateway.RestApi;
import software.amazon.awscdk.services.lambda.Alias;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.ec2.SecurityGroup;
import software.amazon.awscdk.services.ec2.SecurityGroupProps;
import software.constructs.Construct;

import software.amazon.awscdk.DefaultStackSynthesizer;
import software.amazon.awscdk.DefaultStackSynthesizerProps;

import java.util.List;
import java.util.Map;

public class UnicornStoreStack extends Stack {

    private final InfrastructureCore infrastructureCore;

    public UnicornStoreStack(final Construct scope, final String id) {
        // super(scope, id, props);
        super(scope, id, StackProps.builder()
        .synthesizer(new DefaultStackSynthesizer(DefaultStackSynthesizerProps.builder()
            .generateBootstrapVersionRule(false)  // This disables the bootstrap version parameter
            .build()))
        .build());

        // Create Core infrastructure
        this.infrastructureCore = new InfrastructureCore(this, "InfrastructureCore");
        var accountId = Stack.of(this).getAccount();

        // Execute Database setup
        var databaseSetup = new DatabaseSetup(this, "UnicornDatabaseSetup", infrastructureCore);
        databaseSetup.getNode().addDependency(infrastructureCore.getDatabase());

        // Create security group for IDE to talk to EKS Cluster
        var eksIdeSecurityGroup = new SecurityGroup(this, "EksIdeSecurityGroup",
            SecurityGroupProps
                .builder()
                .securityGroupName("EKS IDE Security Group")
                .vpc(infrastructureCore.getVpc())
                .allowAllOutbound(false)
                .build());
        // Add ingress rule to allow all traffic from within the same security group
        eksIdeSecurityGroup.getConnections().allowInternally(
            Port.allTraffic(),
            "Allow all internal traffic"
        );

        // Create Workshop IDE
        var workshopIde = new WorkshopIde(this, "WorkshopIde", infrastructureCore, eksIdeSecurityGroup);
        var ideRole = workshopIde.getIdeRole();

        // Create UnicornStoreLambda
        new UnicornStoreLambda(this, "UnicornStoreLambda", infrastructureCore);

        // Create Immersion Day additional infrastructure
        new InfrastructureImmDay(this, "InfrastructureImmDay", infrastructureCore);

        // Create EKS cluster for the workshop
        var unicornStoreEksCluster = new EksCluster(this, "UnicornStoreEksCluster", "unicorn-store", "1.31",
            infrastructureCore.getVpc(), eksIdeSecurityGroup);
        unicornStoreEksCluster.createAccessEntry(ideRole.getRoleArn());
        var isWorkshopStudioAccount = CfnParameter.Builder.create(this, "IsWorkshopStudioAccount")
            .type("String")
            .defaultValue("no")
            .build();
        if ("yes".equals(isWorkshopStudioAccount.getValueAsString())) {
            unicornStoreEksCluster.createAccessEntry("arn:aws:iam::" + accountId + ":role/WSParticipantRole");
        }


        // var eventBridge = infrastructureConstruct.getEventBridge();

        // //Create Spring Lambda function
        // var unicornStoreSpringLambda = createUnicornLambdaFunction();

        // //Permission for Spring Boot Lambda Function
        // eventBridge.grantPutEventsTo(unicornStoreSpringLambda);

        // //Setup a Proxy-Rest API to access the Spring Lambda function
        // var restApi = setupRestApi(unicornStoreSpringLambda);

        // //Create output values for later reference
        // new CfnOutput(this, "unicorn-store-spring-function-arn", CfnOutputProps.builder()
        //         .value(unicornStoreSpringLambda.getFunctionArn())
        //         .build());

        // new CfnOutput(this, "ApiEndpointSpring", CfnOutputProps.builder()
        //         .value(restApi.getUrl())
        //         .build());
    }

    // private RestApi setupRestApi(Alias unicornStoreSpringLambdaAlias) {
    //     return LambdaRestApi.Builder.create(this, "UnicornStoreSpringApi")
    //             .restApiName("UnicornStoreSpringApi")
    //             .handler(unicornStoreSpringLambdaAlias)
    //             .build();
    // }

    // private Alias createUnicornLambdaFunction() {
    //     var lambda = Function.Builder.create(this, "UnicornStoreSpringFunction")
    //             .runtime(Runtime.JAVA_21)
    //             .functionName("unicorn-store-spring")
    //             .memorySize(512)
    //             .timeout(Duration.seconds(29))
    //             .code(Code.fromAsset("../../software/unicorn-store-spring/target/store-spring-1.0.0.jar"))
    //             .handler("com.amazonaws.serverless.proxy.spring.SpringDelegatingLambdaContainerHandler")
    //             .vpc(infrastructureConstruct.getVpc())
    //             .securityGroups(List.of(infrastructureConstruct.getApplicationSecurityGroup()))
    //             .environment(Map.of(
    //                 "MAIN_CLASS", "com.unicorn.store.StoreApplication",
    //                 "SPRING_DATASOURCE_PASSWORD", infrastructureConstruct.getDatabaseSecretString(),
    //                 "SPRING_DATASOURCE_URL", infrastructureConstruct.getDatabaseJDBCConnectionString(),
    //                 "SPRING_DATASOURCE_HIKARI_maximumPoolSize", "1",
    //                 "AWS_SERVERLESS_JAVA_CONTAINER_INIT_GRACE_TIME", "500"
    //             ))
    //             .build();

    //     // Create an alias for the latest version
    //     var alias = Alias.Builder.create(this, "UnicornStoreSpringFunctionAlias")
    //             .aliasName("live")
    //             .version(lambda.getLatestVersion())
    //             .build();

    //     return alias;
    // }

}
