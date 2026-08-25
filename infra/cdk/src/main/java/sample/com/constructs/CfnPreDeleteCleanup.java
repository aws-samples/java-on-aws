package sample.com.constructs;

import software.amazon.awscdk.ArnComponents;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.s3.IBucket;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * CfnPreDeleteCleanup construct for cleaning up resources before stack deletion.
 * - GuardDuty VPC endpoints that block VPC deletion
 * - CloudWatch log groups with workshop- or unicornstore- prefix
 * - S3 bucket contents for workshop- buckets
 */
public class CfnPreDeleteCleanup extends Construct {

    public static class CfnPreDeleteCleanupProps {
        private String prefix = "workshop";
        private IVpc vpc;
        private List<IBucket> buckets = List.of();

        public static Builder builder() { return new Builder(); }

        public static class Builder {
            private CfnPreDeleteCleanupProps props = new CfnPreDeleteCleanupProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public Builder vpc(IVpc vpc) { props.vpc = vpc; return this; }
            public Builder buckets(List<IBucket> buckets) { props.buckets = List.copyOf(buckets); return this; }
            public CfnPreDeleteCleanupProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
        public IVpc getVpc() { return vpc; }
        public List<IBucket> getBuckets() { return buckets; }
    }

    public CfnPreDeleteCleanup(final Construct scope, final String id, final CfnPreDeleteCleanupProps props) {
        super(scope, id);

        String prefix = props.getPrefix();

        // Create Lambda role with permissions for cleanup operations
        Role lambdaRole = Role.Builder.create(this, "Role")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
            ))
            .build();

        // Add EC2 permissions for VPC endpoint and security group operations
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "ec2:DescribeVpcEndpoints",
                "ec2:DescribeSecurityGroups"
            ))
            .resources(List.of("*"))
            .build());

        String vpcArn = Stack.of(this).formatArn(ArnComponents.builder()
            .service("ec2")
            .resource("vpc")
            .resourceName(props.getVpc().getVpcId())
            .build());

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ec2:DeleteVpcEndpoints"))
            .resources(List.of(Stack.of(this).formatArn(ArnComponents.builder()
                .service("ec2")
                .resource("vpc-endpoint")
                .resourceName("*")
                .build())))
            .conditions(Map.of("StringEquals", Map.of("ec2:Vpc", vpcArn)))
            .build());

        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ec2:DeleteSecurityGroup"))
            .resources(List.of(Stack.of(this).formatArn(ArnComponents.builder()
                .service("ec2")
                .resource("security-group")
                .resourceName("*")
                .build())))
            .conditions(Map.of("StringEquals", Map.of("ec2:Vpc", vpcArn)))
            .build());

        // Add S3 permissions for bucket cleanup
        for (IBucket bucket : props.getBuckets()) {
            lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("s3:DeleteBucket", "s3:ListBucket", "s3:ListBucketVersions"))
                .resources(List.of(bucket.getBucketArn()))
                .build());
            lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("s3:DeleteObject", "s3:DeleteObjectVersion"))
                .resources(List.of(bucket.arnForObjects("*")))
                .build());
        }

        // Create cleanup Lambda function
        Function cleanupFunction = Function.Builder.create(this, "Function")
            .functionName(prefix + "-cfn-pre-delete-cleanup")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.lambda_handler")
            .code(Code.fromInline(loadFile("/lambda/cfn-pre-delete-cleanup.py")))
            .role(lambdaRole)
            .timeout(Duration.minutes(10))
            .description("Cleanup VPC endpoints, CloudWatch logs, and S3 buckets before stack deletion")
            .build();

        // Create Custom Resource that triggers cleanup on stack delete
        CustomResource.Builder.create(this, "Resource")
            .serviceToken(cleanupFunction.getFunctionArn())
            .properties(Map.of(
                "VpcId", props.getVpc().getVpcId(),
                "BucketNames", props.getBuckets().stream().map(IBucket::getBucketName).toList()
            ))
            .build();
    }

    private String loadFile(String filePath) {
        try {
            var resource = getClass().getResource(filePath);
            if (resource == null) {
                throw new RuntimeException("Resource file not found: " + filePath);
            }
            return Files.readString(Path.of(resource.getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }
}
