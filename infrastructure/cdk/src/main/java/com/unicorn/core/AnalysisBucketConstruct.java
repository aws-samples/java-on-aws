package com.unicorn.core;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.s3.*;
import software.constructs.Construct;

import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;

public class AnalysisBucketConstruct extends Construct {
    private final Bucket bucket;

    public AnalysisBucketConstruct(final Construct scope, final String id, AnalysisBucketProps props) {
        super(scope, id);

        // Generate unique timestamp
        String timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
                .replaceAll("[-:.]", "");

        // Create the S3 bucket
        this.bucket = Bucket.Builder.create(this, "AnalysisBucket")
                .bucketName(props.getBucketPrefix() + "-" + timestamp)
                .encryption(BucketEncryption.S3_MANAGED)
                .versioned(props.isVersioningEnabled())
                .publicReadAccess(false)
                .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
                .removalPolicy(props.getRemovalPolicy())
                .lifecycleRules(Arrays.asList(
                        LifecycleRule.builder()
                                .enabled(true)
                                .expiration(Duration.days(props.getRetentionDays()))
                                .build(),
                        LifecycleRule.builder()
                                .enabled(true)
                                .noncurrentVersionExpiration(Duration.days(props.getNoncurrentVersionRetentionDays()))
                                .build()
                ))
                .build();
    }

    public Bucket getBucket() {
        return bucket;
    }
}