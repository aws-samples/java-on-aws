package sample.com.constructs;

import software.amazon.awscdk.Aws;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.s3.BlockPublicAccess;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.constructs.Construct;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * WorkshopBucket construct for shared workshop resources.
 * Creates S3 bucket and SSM parameter for bucket name discovery.
 */
public class WorkshopBucket extends Construct {

    private final Bucket bucket;
    private final StringParameter bucketNameParameter;

    public static class WorkshopBucketProps {
        private String prefix = "workshop";

        public static WorkshopBucketProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private WorkshopBucketProps props = new WorkshopBucketProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public WorkshopBucketProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
    }

    public WorkshopBucket(final Construct scope, final String id) {
        this(scope, id, WorkshopBucketProps.builder().build());
    }

    public WorkshopBucket(final Construct scope, final String id, final WorkshopBucketProps props) {
        super(scope, id);

        String prefix = props.getPrefix();
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"));

        // Create S3 bucket for workshop data (thread dumps, profiling data)
        // Note: autoDeleteObjects removed - CfnPreDeleteCleanup Lambda handles bucket emptying
        this.bucket = Bucket.Builder.create(this, "Bucket")
            .bucketName(String.format("%s-bucket-%s-%s-%s", prefix, Aws.ACCOUNT_ID, Aws.REGION, timestamp))
            .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
            .enforceSsl(true)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        // Create SSM parameter for bucket name discovery
        this.bucketNameParameter = StringParameter.Builder.create(this, "BucketNameParameter")
            .parameterName(prefix + "-bucket-name")
            .description("Workshop bucket name for thread dumps and profiling data")
            .stringValue(bucket.getBucketName())
            .build();
    }

    // Getters
    public Bucket getBucket() {
        return bucket;
    }

    public StringParameter getBucketNameParameter() {
        return bucketNameParameter;
    }
}
