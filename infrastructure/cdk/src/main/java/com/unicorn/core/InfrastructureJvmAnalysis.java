package com.unicorn.core;

import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.ArnPrincipal;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.apprunner.alpha.VpcConnector;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.constructs.Construct;

import java.util.List;

// Additional infrastructure for Containers modules of Java on AWS Immersion Day
public class InfrastructureJvmAnalysis extends Construct {

    private final Bucket s3Bucket;

    public InfrastructureJvmAnalysis(final Construct scope, final String id, Bucket s3Bucket) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.s3Bucket = s3Bucket;

        createJvmAnalysisServiceEcr();
        createRolesEks();
    }

    private Repository createJvmAnalysisServiceEcr() {
        return Repository.Builder.create(this, "JvmAnalysisServiceEcr")
            .repositoryName("jvm-analysis-service")
            .imageScanOnPush(false)
            .removalPolicy(RemovalPolicy.DESTROY)
            .emptyOnDelete(true)  // This will force delete all images when repository is deleted
            .build();
    }

    private void createRolesEks() {
        ServicePrincipal eksPods = new ServicePrincipal("pods.eks.amazonaws.com");

        // EKS Pod Identity role
        var jvmAnalysisServiceEksPodRole = Role.Builder.create(this, "JvmAnalysisServiceEksPodRole")
            .roleName("jvm-analysis-service-eks-pod-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        jvmAnalysisServiceEksPodRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "JvmAnalysisServiceEksPodRole-" + "AmazonBedrockLimitedAccess",
            "arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"));
        // add permission to list read put to bucket Bucket
        jvmAnalysisServiceEksPodRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("s3:ListBucket", "s3:GetObject", "s3:PutObject"))
            .resources(List.of(s3Bucket.getBucketArn(), s3Bucket.getBucketArn() + "/*"))
            .build());
    }
}
