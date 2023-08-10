package com.unicorn;

import com.unicorn.core.InfrastructureStack;
import com.unicorn.core.VpcStack;
import io.github.cdklabs.cdknag.AwsSolutionsChecks;
import io.github.cdklabs.cdknag.NagPackSuppression;
import io.github.cdklabs.cdknag.NagSuppressions;
import software.amazon.awscdk.App;
import software.amazon.awscdk.Aspects;
import software.amazon.awscdk.StackProps;

import java.util.List;

public class UnicornStoreApp {

    public static void main(final String[] args) {
        App app = new App();

        var vpcStack = new VpcStack(app, "UnicornStoreVpc", StackProps.builder().build());

        var infrastructureStack = new InfrastructureStack(app, "UnicornStoreInfrastructure",
            StackProps.builder().build(), vpcStack);

        var unicornStoreLambdaApp = new UnicornStoreLambdaStack(app, "UnicornStoreLambdaApp", StackProps.builder()
                .build(), infrastructureStack);

        var stackName = "UnicornStoreSpring";
        var projectName = "unicorn-store-spring";
        var unicornStoreSpringCI = new UnicornStoreCIStack(app, stackName + "CI", StackProps.builder()
                .build(), infrastructureStack, projectName);

        var unicornStoreSpringECS = new UnicornStoreECSStack(app, stackName + "ECS", StackProps.builder()
                .build(), infrastructureStack, projectName);

        var unicornStoreSpringEKS = new UnicornStoreEKSStack(app, stackName + "EKS", StackProps.builder()
                .build(), infrastructureStack, projectName);

        //Add CDK-NAG checks: https://github.com/cdklabs/cdk-nag
        //Add suppression to exclude certain findings that are not needed for Workshop environment
        Aspects.of(app).add(new AwsSolutionsChecks());
        var suppressionVpc = List.of(
            new NagPackSuppression.Builder().id("AwsSolutions-VPC7").reason("Workshop environment does not need VPC flow logs").build()
        );
        NagSuppressions.addStackSuppressions(vpcStack, suppressionVpc);

        var suppression = List.of(
            new NagPackSuppression.Builder().id("AwsSolutions-APIG4").reason("The workshop environment does not require API-Gateway authorization").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-COG4").reason("The workshop environment does not require Cognito User Pool authorization").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS3").reason("Workshop environment does not need a Multi-AZ setup to reduce cost").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-IAM4").reason("AWS Managed policies are acceptable for the workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-IAM5").reason("Wildcard permissions are acceptable for the workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS10").reason("Workshop environment is ephemeral and the database should be deleted by the end of the workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS11").reason("Database is in a private subnet and can use the default port").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG2").reason("API Gateway request validation is not needed for workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG1").reason("API Gateway access logging not needed for workshop setup").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG6").reason("API Gateway access logging not needed for workshop setup").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-SMG4").reason("Ephemeral workshop environment does not need to rotate secrets").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS2").reason("Workshop non-sensitive test database does not need encryption at rest").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG3").reason("Workshop API Gateways do not need AWS WAF assigned" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-S1").reason("Workshop S3 bucket does not need Access Logs" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS13").reason("Workshop Database does not need backups" ).build()
        );

        NagSuppressions.addStackSuppressions(infrastructureStack, suppression);
        NagSuppressions.addStackSuppressions(unicornStoreLambdaApp, suppression);

        var suppressionCICD = List.of(
            new NagPackSuppression.Builder().id("AwsSolutions-CB3").reason("CodeBuild uses privileged mode to build docker images" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-CB4").reason("CodeBuild uses default AWS-managed CMK for S3" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-S1").reason("CodePipeline uses S3 to store temporary artefacts" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-IAM5").reason("CodeBuild uses default permissions for PipelineProject" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-ELB2").reason("Workshop environment does not need ELB access logs" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-EC23").reason("ELB is accessible from the Internet to allow application testing" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-ECS2").reason("Application need environment variables to accees workshop DB" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-IAM4").reason("AWS Managed policies are acceptable for the workshop" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-IAM5").reason("Workshop environment use CDK default execution role for Kubectl Lamdas" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-L1").reason("Workshop environment use CDK default Labdas for Kubectl" ).build(),
            new NagPackSuppression.Builder().id("AwsSolutions-EKS1").reason("Workshop non-sensitive EKS cluster uses public access" ).build()
        );

        NagSuppressions.addStackSuppressions(unicornStoreSpringCI, suppressionCICD);
        NagSuppressions.addStackSuppressions(unicornStoreSpringECS, suppressionCICD);
        NagSuppressions.addStackSuppressions(unicornStoreSpringEKS, suppressionCICD, true);

        app.synth();
    }
}
