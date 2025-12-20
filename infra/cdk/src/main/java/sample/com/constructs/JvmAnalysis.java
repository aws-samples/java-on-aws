package sample.com.constructs;

import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;

/**
 * JvmAnalysis construct for JVM profiling analysis.
 * Creates ECR repository and Pod Identity role for jvm-analysis-service.
 * Uses app-specific naming (no prefix) for workshop content compatibility.
 */
public class JvmAnalysis extends Construct {

    private final Repository jvmAnalysisEcr;
    private final Role jvmAnalysisServiceRole;

    public static class JvmAnalysisProps {
        private Bucket workshopBucket;

        public static JvmAnalysisProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private JvmAnalysisProps props = new JvmAnalysisProps();

            public Builder workshopBucket(Bucket workshopBucket) { props.workshopBucket = workshopBucket; return this; }
            public JvmAnalysisProps build() { return props; }
        }

        public Bucket getWorkshopBucket() { return workshopBucket; }
    }

    public JvmAnalysis(final Construct scope, final String id) {
        this(scope, id, JvmAnalysisProps.builder().build());
    }

    public JvmAnalysis(final Construct scope, final String id, final JvmAnalysisProps props) {
        super(scope, id);

        // Create ECR repository for jvm-analysis-service (app-specific naming, no prefix)
        this.jvmAnalysisEcr = Repository.Builder.create(this, "Ecr")
            .repositoryName("jvm-analysis-service")
            .removalPolicy(RemovalPolicy.DESTROY)
            .emptyOnDelete(true)
            .build();

        // Create Pod Identity role for jvm-analysis-service (app-specific naming, no prefix)
        // Pod Identity requires both sts:AssumeRole and sts:TagSession
        CompositePrincipal podIdentityPrincipal = new CompositePrincipal(
            ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()
        );

        this.jvmAnalysisServiceRole = Role.Builder.create(this, "ServiceRole")
            .roleName("jvm-analysis-service-eks-pod-role")
            .assumedBy(podIdentityPrincipal)
            .description("Role for jvm-analysis-service EKS pod to access Bedrock and S3")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess")
            ))
            .build();

        // Add sts:TagSession to the assume role policy for Pod Identity
        PolicyDocument assumeRolePolicy = jvmAnalysisServiceRole.getAssumeRolePolicy();
        if (assumeRolePolicy != null) {
            assumeRolePolicy.addStatements(
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .principals(List.of(ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()))
                    .actions(List.of("sts:TagSession"))
                    .build()
            );
        }

        // Add S3 permissions for profiling data
        if (props.getWorkshopBucket() != null) {
            jvmAnalysisServiceRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:PutObject"
                ))
                .resources(List.of(
                    props.getWorkshopBucket().getBucketArn(),
                    props.getWorkshopBucket().getBucketArn() + "/*"
                ))
                .build());
        }
    }

    // Getters
    public Repository getJvmAnalysisEcr() {
        return jvmAnalysisEcr;
    }

    public Role getJvmAnalysisServiceRole() {
        return jvmAnalysisServiceRole;
    }
}
