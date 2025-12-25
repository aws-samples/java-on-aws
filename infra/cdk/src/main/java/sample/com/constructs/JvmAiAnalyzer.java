package sample.com.constructs;

import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;

/**
 * JvmAiAnalyzer construct for JVM profiling analysis.
 * Creates Pod Identity role for jvm-ai-analyzer.
 * Uses app-specific naming (no prefix) for workshop content compatibility.
 *
 * Note: ECR repository (jvm-ai-analyzer) is now created automatically via
 * ECR Repository Creation Template (create-on-push) instead of explicit definition.
 */
public class JvmAiAnalyzer extends Construct {

    private final Role jvmAiAnalyzerRole;

    public static class JvmAiAnalyzerProps {
        private Bucket workshopBucket;

        public static JvmAiAnalyzerProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private JvmAiAnalyzerProps props = new JvmAiAnalyzerProps();

            public Builder workshopBucket(Bucket workshopBucket) { props.workshopBucket = workshopBucket; return this; }
            public JvmAiAnalyzerProps build() { return props; }
        }

        public Bucket getWorkshopBucket() { return workshopBucket; }
    }

    public JvmAiAnalyzer(final Construct scope, final String id) {
        this(scope, id, JvmAiAnalyzerProps.builder().build());
    }

    public JvmAiAnalyzer(final Construct scope, final String id, final JvmAiAnalyzerProps props) {
        super(scope, id);

        // Note: ECR repository (jvm-ai-analyzer) is created automatically via
        // ECR Repository Creation Template when images are pushed

        // Create Pod Identity role for jvm-ai-analyzer (app-specific naming, no prefix)
        // Pod Identity requires both sts:AssumeRole and sts:TagSession
        CompositePrincipal podIdentityPrincipal = new CompositePrincipal(
            ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()
        );

        this.jvmAiAnalyzerRole = Role.Builder.create(this, "ServiceRole")
            .roleName("jvm-ai-analyzer-eks-pod-role")
            .assumedBy(podIdentityPrincipal)
            .description("Role for jvm-ai-analyzer EKS pod to access Bedrock and S3")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess")
            ))
            .build();

        // Add sts:TagSession to the assume role policy for Pod Identity
        PolicyDocument assumeRolePolicy = jvmAiAnalyzerRole.getAssumeRolePolicy();
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
            jvmAiAnalyzerRole.addToPolicy(PolicyStatement.Builder.create()
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
    public Role getJvmAiAnalyzerRole() {
        return jvmAiAnalyzerRole;
    }
}
