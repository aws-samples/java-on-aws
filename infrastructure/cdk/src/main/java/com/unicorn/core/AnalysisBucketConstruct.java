package com.unicorn.core;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.s3.*;
import software.constructs.Construct;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;

public class AnalysisBucketConstruct extends Construct {
    private final Bucket bucket;

    public AnalysisBucketConstruct(final Construct scope, final String id, AnalysisBucketProps props) {
        super(scope, id);

        // Safe timestamp format for S3 bucket name
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
                .withZone(ZoneOffset.UTC);
        String timestamp = formatter.format(Instant.now());

        // Generate a lowercase, valid bucket name
        String rawName = props.getBucketPrefix() + "-" + timestamp;
        String bucketName = rawName.toLowerCase().replaceAll("[^a-z0-9.-]", "");

        // Trim trailing non-alphanumeric characters (e.g. dash)
        bucketName = bucketName.replaceAll("[-.]+$", "");

        // Create the S3 bucket
        this.bucket = Bucket.Builder.create(this, "AnalysisBucket")
                .bucketName(bucketName)
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