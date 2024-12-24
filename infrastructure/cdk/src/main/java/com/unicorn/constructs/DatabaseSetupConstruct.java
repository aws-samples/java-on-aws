package com.unicorn.constructs;

import com.unicorn.core.InfrastructureConstruct;
// import software.amazon.awscdk.CfnOutput;
// import software.amazon.awscdk.CfnOutputProps;
import software.amazon.awscdk.Duration;
// import software.amazon.awscdk.services.ec2.IInterfaceVpcEndpoint;
// import software.amazon.awscdk.services.ec2.InterfaceVpcEndpoint;
// import software.amazon.awscdk.services.ec2.InterfaceVpcEndpointAwsService;
// import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.CustomResource;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

public class DatabaseSetupConstruct extends Construct{

    private final InfrastructureConstruct infrastructureConstruct;
    private CustomResource databaseSetupResource;

    public DatabaseSetupConstruct(final Construct scope, final String id,
        final InfrastructureConstruct infrastructureConstruct) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureConstruct = infrastructureConstruct;

        if (databaseSetupResource == null) {
            Function databaseSetupFunction = Function.Builder.create(this, "DatabaseSetupFunction")
                .code(Code.fromInline(loadFile("/database-setup.py")))
                .handler("index.lambda_handler")
                .runtime(Runtime.PYTHON_3_13)
                .functionName("database-setup")
                .timeout(Duration.minutes(3))
                .vpc(infrastructureConstruct.getVpc())
                .securityGroups(List.of(infrastructureConstruct.getApplicationSecurityGroup()))
                .build();

            infrastructureConstruct.getDatabaseSecret().grantRead(databaseSetupFunction);
            infrastructureConstruct.getDatabase().grantDataApiAccess(databaseSetupFunction);

            databaseSetupResource = CustomResource.Builder.create(this, "DatabaseSetupResource")
                .serviceToken(databaseSetupFunction.getFunctionArn())
                .properties(Map.of(
                    "SecretName", infrastructureConstruct.getDatabaseSecret().getSecretName(),
                    "SqlStatements", loadFile("/schema.sql")
                ))
                .build();
        }

        // var dbSetupLambdaFunction = createDbSetupLambdaFunction();
        // dbSetupLambdaFunction.addToRolePolicy(PolicyStatement
        //         .Builder
        //         .create()
        //         .resources(List.of("arn:aws:secretsmanager:*:*:secret:unicornstore-db-secret-*"))
        //         .actions(List.of("secretsmanager:GetSecretValue"))
        //         .build());
        // createSecretsManagerVpcEndpoint();

        // new CfnOutput(scope, "DbSetupArn", CfnOutputProps.builder()
        //         .value(dbSetupLambdaFunction.getFunctionArn())
        //         .build());
    }

    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }

    // private Function createDbSetupLambdaFunction() {
    //     return Function.Builder.create(this, "DBSetupLambdaFunction")
    //             .runtime(Runtime.JAVA_21)
    //             .memorySize(1024)
    //             .timeout(Duration.seconds(29))
    //             .code(Code.fromInline(""))
    //             // .code(Code.fromAsset("../db-setup/target/db-setup.jar"))
    //             .handler("com.amazon.aws.DBSetupHandler::handleRequest")
    //             .vpc(infrastructureConstruct.getVpc())
    //             .securityGroups(List.of(infrastructureConstruct.getApplicationSecurityGroup()))
    //             .build();
    // }

    // private IInterfaceVpcEndpoint createSecretsManagerVpcEndpoint() {
    //     return InterfaceVpcEndpoint.Builder.create(this, "SecretsManagerEndpoint")
    //             .service(InterfaceVpcEndpointAwsService.SECRETS_MANAGER)
    //             .vpc(infrastructureConstruct.getVpc())
    //             .build();
    // }
}
