package com.unicorn.core;

// AnalysisBucketProps.java

import software.amazon.awscdk.RemovalPolicy;

public class AnalysisBucketProps {
    private final String bucketPrefix;
    private final boolean versioningEnabled;
    private final int retentionDays;
    private final int noncurrentVersionRetentionDays;
    private final RemovalPolicy removalPolicy;

    private AnalysisBucketProps(Builder builder) {
        this.bucketPrefix = builder.bucketPrefix;
        this.versioningEnabled = builder.versioningEnabled;
        this.retentionDays = builder.retentionDays;
        this.noncurrentVersionRetentionDays = builder.noncurrentVersionRetentionDays;
        this.removalPolicy = builder.removalPolicy;
    }

    public String getBucketPrefix() {
        return bucketPrefix;
    }

    public boolean isVersioningEnabled() {
        return versioningEnabled;
    }

    public int getRetentionDays() {
        return retentionDays;
    }

    public int getNoncurrentVersionRetentionDays() {
        return noncurrentVersionRetentionDays;
    }

    public RemovalPolicy getRemovalPolicy() {
        return removalPolicy;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static class Builder {
        private String bucketPrefix = "analysis";
        private boolean versioningEnabled = true;
        private int retentionDays = 90;
        private int noncurrentVersionRetentionDays = 30;
        private RemovalPolicy removalPolicy = RemovalPolicy.RETAIN;

        public Builder bucketPrefix(String bucketPrefix) {
            this.bucketPrefix = bucketPrefix;
            return this;
        }

        public Builder versioningEnabled(boolean versioningEnabled) {
            this.versioningEnabled = versioningEnabled;
            return this;
        }

        public Builder retentionDays(int retentionDays) {
            this.retentionDays = retentionDays;
            return this;
        }

        public Builder noncurrentVersionRetentionDays(int noncurrentVersionRetentionDays) {
            this.noncurrentVersionRetentionDays = noncurrentVersionRetentionDays;
            return this;
        }

        public Builder removalPolicy(RemovalPolicy removalPolicy) {
            this.removalPolicy = removalPolicy;
            return this;
        }

        public AnalysisBucketProps build() {
            return new AnalysisBucketProps(this);
        }
    }
}
