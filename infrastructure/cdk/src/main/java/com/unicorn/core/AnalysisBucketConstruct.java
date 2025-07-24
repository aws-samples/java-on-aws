package com.unicorn.core;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.iam.AnyPrincipal;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.s3.*;
import software.constructs.Construct;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

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
        bucketName = bucketName.replaceAll("[-.]+$", ""); // Remove trailing dashes/dots

        // Create the S3 bucket
        this.bucket = Bucket.Builder.create(this, "AnalysisBucket")
                .bucketName(bucketName)
                .encryption(BucketEncryption.S3_MANAGED)
                .versioned(props.isVersioningEnabled())
                .publicReadAccess(false)
                .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
                .removalPolicy(props.getRemovalPolicy())
                .lifecycleRules(List.of(
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

        // Enforce SSL access with a bucket policy (CDK Nag: AwsSolutions-S10)
        bucket.addToResourcePolicy(PolicyStatement.Builder.create()
                .sid("EnforceSSLOnly")
                .effect(Effect.DENY)
                .principals(List.of(new AnyPrincipal()))
                .actions(List.of("s3:*"))
                .resources(List.of(
                        bucket.getBucketArn(),
                        bucket.getBucketArn() + "/*"
                ))
                .conditions(Map.of(
                        "Bool", Map.of("aws:SecureTransport", "false")
                ))
                .build());
    }

    public Bucket getBucket() {
        return bucket;
    }
}