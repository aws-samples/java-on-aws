package sample.com;

import io.github.cdklabs.cdknag.AwsSolutionsChecks;
import io.github.cdklabs.cdknag.NagPackSuppression;
import io.github.cdklabs.cdknag.NagSuppressions;
import software.amazon.awscdk.App;
import software.amazon.awscdk.AppProps;
import software.amazon.awscdk.Aspects;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.DefaultStackSynthesizer;
import software.amazon.awscdk.DefaultStackSynthesizerProps;

import java.util.List;

public class WorkshopApp {
    public static void main(final String[] args) {
        App app = new App(AppProps.builder()
            .analyticsReporting(false)
            .build());

        var workshopStack = new WorkshopStack(app, "WorkshopStack", StackProps.builder()
            .synthesizer(new DefaultStackSynthesizer(DefaultStackSynthesizerProps.builder()
                .generateBootstrapVersionRule(false)
                .build()))
            .build());

        // Add CDK-NAG checks: https://github.com/cdklabs/cdk-nag
        Aspects.of(app).add(new AwsSolutionsChecks());

        // Workshop environment suppressions - these are acceptable for ephemeral workshop environments
        var suppressions = List.of(
            // API Gateway
            new NagPackSuppression.Builder().id("AwsSolutions-APIG1").reason("API Gateway access logging not needed for workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG2").reason("API Gateway request validation not needed for workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG3").reason("Workshop API Gateways do not need AWS WAF").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG4").reason("Workshop environment does not require API Gateway authorization").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-APIG6").reason("API Gateway access logging not needed for workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-COG4").reason("Workshop environment does not require Cognito User Pool authorization").build(),

            // IAM
            new NagPackSuppression.Builder().id("AwsSolutions-IAM4").reason("AWS Managed policies are acceptable for workshop").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-IAM5").reason("Wildcard permissions acceptable for workshop parallel resource creation").build(),

            // RDS
            new NagPackSuppression.Builder().id("AwsSolutions-RDS2").reason("Workshop non-sensitive test database does not need encryption at rest").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS3").reason("Workshop environment does not need Multi-AZ to reduce cost").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS6").reason("Workshop environment uses user/password authentication").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS10").reason("Workshop environment is ephemeral - database deleted at end").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS11").reason("Database in private subnet can use default port").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-RDS13").reason("Workshop database does not need backups").build(),

            // VPC & Networking
            new NagPackSuppression.Builder().id("AwsSolutions-VPC7").reason("Workshop environment does not need VPC flow logs").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-EC23").reason("Workshop security groups allow broad access for learning").build(),

            // Secrets Manager
            new NagPackSuppression.Builder().id("AwsSolutions-SMG4").reason("Ephemeral workshop environment does not need secret rotation").build(),

            // CloudFront
            new NagPackSuppression.Builder().id("AwsSolutions-CFR1").reason("Workshop environment should be accessible from any geo").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-CFR2").reason("Ephemeral workshop environment does not need WAF").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-CFR3").reason("Ephemeral workshop environment does not need logging").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-CFR4").reason("Workshop IDE uses HTTP origin").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-CFR5").reason("Workshop IDE uses HTTP origin").build(),

            // EKS
            new NagPackSuppression.Builder().id("AwsSolutions-EKS1").reason("Workshop EKS cluster uses public access for learning").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-EKS2").reason("Workshop EKS cluster does not need control plane logging").build(),

            // EC2 & Auto Scaling
            new NagPackSuppression.Builder().id("AwsSolutions-EC28").reason("Workshop instance does not need detailed monitoring").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-EC29").reason("Workshop instance does not need termination protection").build(),

            // CodeBuild
            new NagPackSuppression.Builder().id("AwsSolutions-CB4").reason("CodeBuild uses default AWS-managed CMK for S3").build(),

            // S3
            new NagPackSuppression.Builder().id("AwsSolutions-S1").reason("Workshop S3 bucket does not need access logs").build(),

            // Lambda
            new NagPackSuppression.Builder().id("AwsSolutions-L1").reason("Workshop environment uses CDK default Lambda runtimes").build(),

            // ELB
            new NagPackSuppression.Builder().id("AwsSolutions-ELB2").reason("Workshop environment does not need ALB logs").build(),

            // ECS
            new NagPackSuppression.Builder().id("AwsSolutions-ECS2").reason("Workshop environment uses temporary containers").build(),
            new NagPackSuppression.Builder().id("AwsSolutions-ECS4").reason("Workshop environment does not need Container Insights").build(),

            // CDK Nag validation
            new NagPackSuppression.Builder().id("CdkNagValidationFailure").reason("Suppress CDK Nag validation warnings").build()
        );

        NagSuppressions.addStackSuppressions(workshopStack, suppressions);

        app.synth();
    }
}