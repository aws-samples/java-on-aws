package sample.com.constructs;

import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;

/**
 * PerfPlatform construct for the agentic performance platform (perf-analyzer module).
 * Creates three IAM roles used by the platform components:
 *  - perf-analyzer-eks-pod-role   (perf-analyzer Spring Boot service on EKS)
 *  - perf-collector-eks-pod-role  (perf-collector DaemonSet on EKS)
 *  - perf-collector-ecs-task-role (perf-collector sidecar on ECS Fargate)
 *
 * Uses app-specific role names (no prefix) for workshop content compatibility.
 *
 * Note: ECR repositories (perf-analyzer, perf-collector) are created automatically
 * via ECR Repository Creation Template when images are first pushed.
 */
public class PerfPlatform extends Construct {

    private final Role perfAnalyzerEksPodRole;
    private final Role perfCollectorEksPodRole;
    private final Role perfCollectorEcsTaskRole;

    public static class PerfPlatformProps {
        private Bucket workshopBucket;

        public static PerfPlatformProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private PerfPlatformProps props = new PerfPlatformProps();

            public Builder workshopBucket(Bucket workshopBucket) { props.workshopBucket = workshopBucket; return this; }
            public PerfPlatformProps build() { return props; }
        }

        public Bucket getWorkshopBucket() { return workshopBucket; }
    }

    public PerfPlatform(final Construct scope, final String id) {
        this(scope, id, PerfPlatformProps.builder().build());
    }

    public PerfPlatform(final Construct scope, final String id, final PerfPlatformProps props) {
        super(scope, id);

        this.perfAnalyzerEksPodRole = createAnalyzerEksPodRole(props);
        this.perfCollectorEksPodRole = createCollectorEksPodRole(props);
        this.perfCollectorEcsTaskRole = createCollectorEcsTaskRole(props);
    }

    /**
     * perf-analyzer pod role.
     * Trusts pods.eks.amazonaws.com (Pod Identity).
     * Grants Bedrock invocation, workshop-bucket access under perf-platform/*,
     * and ECS DescribeTasks so the analyzer can locate collector sidecars.
     */
    private Role createAnalyzerEksPodRole(PerfPlatformProps props) {
        ServicePrincipal podsPrincipal = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "AnalyzerEksPodRole")
            .roleName("perf-analyzer-eks-pod-role")
            .assumedBy(podsPrincipal)
            .description("Role for perf-analyzer EKS pod to access Bedrock, S3 and ECS")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess")
            ))
            .build();

        addTagSession(role);
        addWorkshopBucketReadWrite(role, props, "perf-platform/*");
        addEcsDescribeTasks(role);

        return role;
    }

    /**
     * perf-collector EKS pod role.
     * Trusts pods.eks.amazonaws.com (Pod Identity).
     * Writes profiling dumps to workshop-bucket under perf-platform/profiling/*.
     */
    private Role createCollectorEksPodRole(PerfPlatformProps props) {
        ServicePrincipal podsPrincipal = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "CollectorEksPodRole")
            .roleName("perf-collector-eks-pod-role")
            .assumedBy(podsPrincipal)
            .description("Role for perf-collector EKS DaemonSet pod to upload profiling artifacts to S3")
            .build();

        addTagSession(role);
        addWorkshopBucketWrite(role, props, "perf-platform/profiling/*");

        return role;
    }

    /**
     * perf-collector ECS Fargate task role.
     * Trusts ecs-tasks.amazonaws.com.
     * Writes profiling dumps to workshop-bucket under perf-platform/profiling/*.
     */
    private Role createCollectorEcsTaskRole(PerfPlatformProps props) {
        ServicePrincipal tasksPrincipal = ServicePrincipal.Builder.create("ecs-tasks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "CollectorEcsTaskRole")
            .roleName("perf-collector-ecs-task-role")
            .assumedBy(tasksPrincipal)
            .description("Role for perf-collector ECS Fargate sidecar to upload profiling artifacts to S3")
            .build();

        addWorkshopBucketWrite(role, props, "perf-platform/profiling/*");

        return role;
    }

    private void addTagSession(Role role) {
        PolicyDocument assumeRolePolicy = role.getAssumeRolePolicy();
        if (assumeRolePolicy != null) {
            assumeRolePolicy.addStatements(
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .principals(List.of(ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build()))
                    .actions(List.of("sts:TagSession"))
                    .build()
            );
        }
    }

    private void addWorkshopBucketReadWrite(Role role, PerfPlatformProps props, String prefix) {
        if (props.getWorkshopBucket() == null) {
            return;
        }
        String bucketArn = props.getWorkshopBucket().getBucketArn();
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("s3:ListBucket"))
            .resources(List.of(bucketArn))
            .build());
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "s3:GetObject",
                "s3:PutObject",
                "s3:HeadObject"
            ))
            .resources(List.of(bucketArn + "/" + prefix))
            .build());
    }

    private void addWorkshopBucketWrite(Role role, PerfPlatformProps props, String prefix) {
        if (props.getWorkshopBucket() == null) {
            return;
        }
        String bucketArn = props.getWorkshopBucket().getBucketArn();
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "s3:PutObject",
                "s3:HeadObject"
            ))
            .resources(List.of(bucketArn + "/" + prefix))
            .build());
    }

    private void addEcsDescribeTasks(Role role) {
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "ecs:DescribeTasks",
                "ecs:ListTasks",
                "ecs:DescribeContainerInstances"
            ))
            .resources(List.of("*"))
            .build());
    }

    // Getters
    public Role getPerfAnalyzerEksPodRole() {
        return perfAnalyzerEksPodRole;
    }

    public Role getPerfCollectorEksPodRole() {
        return perfCollectorEksPodRole;
    }

    public Role getPerfCollectorEcsTaskRole() {
        return perfCollectorEcsTaskRole;
    }
}
