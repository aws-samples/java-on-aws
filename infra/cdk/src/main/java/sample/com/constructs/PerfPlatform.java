package sample.com.constructs;

import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;

/**
 * PerfPlatform construct for the agentic performance platform (perf-analyzer module).
 * Creates four IAM roles used by the platform components on Amazon EKS:
 *  - perf-analyzer-eks-pod-role     (perf-analyzer Spring Boot service)
 *  - perf-collector-eks-pod-role    (perf-collector DaemonSet)
 *  - pyroscope-eks-pod-role         (Pyroscope server, for S3-backed storage)
 *  - grafana-eks-pod-role           (Grafana, to read ALB metrics from CloudWatch)
 *
 * On Amazon ECS Fargate the collector sidecar runs inside the target task and
 * reuses that task's existing role — we add S3-write for profiling artifacts to
 * the workload's own role rather than maintaining a separate task role. This
 * preserves whatever permissions the app container already has (for example
 * CloudWatch / X-Ray writes), and lets the workshop content avoid running any
 * iam:PutRolePolicy commands at runtime.
 *
 * Note: ECR repositories (perf-analyzer, perf-collector) are created automatically
 * via ECR Repository Creation Template when images are first pushed.
 */
public class PerfPlatform extends Construct {

    private final Role perfAnalyzerEksPodRole;
    private final Role perfCollectorEksPodRole;
    private final Role pyroscopeEksPodRole;
    private final Role grafanaEksPodRole;

    public static class PerfPlatformProps {
        private Bucket workshopBucket;
        private IRole unicornEcsTaskRole;

        public static PerfPlatformProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private PerfPlatformProps props = new PerfPlatformProps();

            public Builder workshopBucket(Bucket workshopBucket) { props.workshopBucket = workshopBucket; return this; }
            public Builder unicornEcsTaskRole(IRole unicornEcsTaskRole) { props.unicornEcsTaskRole = unicornEcsTaskRole; return this; }
            public PerfPlatformProps build() { return props; }
        }

        public Bucket getWorkshopBucket() { return workshopBucket; }
        public IRole getUnicornEcsTaskRole() { return unicornEcsTaskRole; }
    }

    public PerfPlatform(final Construct scope, final String id) {
        this(scope, id, PerfPlatformProps.builder().build());
    }

    public PerfPlatform(final Construct scope, final String id, final PerfPlatformProps props) {
        super(scope, id);

        this.perfAnalyzerEksPodRole = createAnalyzerEksPodRole(props);
        this.perfCollectorEksPodRole = createCollectorEksPodRole(props);
        this.pyroscopeEksPodRole = createPyroscopeEksPodRole(props);
        this.grafanaEksPodRole = createGrafanaEksPodRole();
        grantProfilingWriteToUnicornEcsTaskRole(props);
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
     * Pyroscope EKS pod role.
     * Trusts pods.eks.amazonaws.com (Pod Identity).
     * Grants Pyroscope read/write access to the workshop bucket under the
     * dedicated "pyroscope/" prefix where Pyroscope stores its block data,
     * cluster seed file, and compaction artifacts when running in S3-backed
     * single-binary mode. The prefix is separate from the perf-platform/
     * prefix so Pyroscope's lifecycle and the analyzer's artifact lifecycle
     * stay independent.
     */
    private Role createPyroscopeEksPodRole(PerfPlatformProps props) {
        ServicePrincipal podsPrincipal = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "PyroscopeEksPodRole")
            .roleName("pyroscope-eks-pod-role")
            .assumedBy(podsPrincipal)
            .description("Role for Pyroscope server pod to read/write blocks in S3 under pyroscope/*")
            .build();

        addTagSession(role);
        addPyroscopeS3Access(role, props, "pyroscope");

        return role;
    }

    /**
     * Grafana CloudWatch pod role.
     * Trusts pods.eks.amazonaws.com (Pod Identity).
     * Grants the Grafana ServiceAccount in the monitoring namespace read-only
     * access to CloudWatch metrics so the perf-platform alert rule and the
     * Latency Metrics dashboard can query ALB TargetResponseTime, RequestCount,
     * and HTTPCode_Target_5XX_Count for whichever ALB(s) participants deploy
     * during the workshop.
     */
    private Role createGrafanaEksPodRole() {
        ServicePrincipal podsPrincipal = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "GrafanaEksPodRole")
            .roleName("grafana-eks-pod-role")
            .assumedBy(podsPrincipal)
            .description("Role for Grafana to read CloudWatch metrics for the perf-platform Latency Metrics dashboard and ServiceLatency alert")
            .build();

        addTagSession(role);
        // Standard CloudWatch read-only set used by Grafana's CloudWatch datasource.
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "cloudwatch:GetMetricData",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "cloudwatch:DescribeAlarmsForMetric",
                "cloudwatch:DescribeAlarmHistory",
                "cloudwatch:DescribeAlarms",
                "tag:GetResources",
                "ec2:DescribeRegions",
                "ec2:DescribeTags"
            ))
            .resources(List.of("*"))
            .build());
        return role;
    }

    /**
     * Grant the Unicorn ECS task role permissions the perf-collector sidecar needs.
     * Attaches to the existing task role so the sidecar runs under the task's role
     * and the workshop content needs no runtime IAM changes.
     *
     * Permissions added:
     *  - s3:PutObject/HeadObject on workshop-bucket perf-platform/profiling/*
     *  - ecs:DescribeTasks on all tasks (Fargate task-metadata endpoint does not
     *    expose task tags; the sidecar must call the ECS API to read them).
     */
    private void grantProfilingWriteToUnicornEcsTaskRole(PerfPlatformProps props) {
        if (props.getUnicornEcsTaskRole() == null || props.getWorkshopBucket() == null) {
            return;
        }
        String bucketArn = props.getWorkshopBucket().getBucketArn();
        props.getUnicornEcsTaskRole().addToPrincipalPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "s3:PutObject",
                "s3:HeadObject"
            ))
            .resources(List.of(bucketArn + "/perf-platform/profiling/*"))
            .build());
        props.getUnicornEcsTaskRole().addToPrincipalPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("ecs:DescribeTasks"))
            .resources(List.of("*"))
            .build());
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

    /**
     * Pyroscope needs more than simple write: in S3-backed single-binary mode it
     * lists the prefix to discover blocks, reads blocks during queries, writes
     * new blocks, uses multipart uploads for large blocks, and deletes blocks
     * during compaction and retention enforcement.
     */
    private void addPyroscopeS3Access(Role role, PerfPlatformProps props, String prefix) {
        if (props.getWorkshopBucket() == null) {
            return;
        }
        String bucketArn = props.getWorkshopBucket().getBucketArn();
        // Bucket-level list, scoped to the prefix.
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("s3:ListBucket", "s3:GetBucketLocation"))
            .resources(List.of(bucketArn))
            .conditions(java.util.Map.of(
                "StringLike", java.util.Map.of(
                    "s3:prefix", List.of(prefix + "/*", prefix)
                )
            ))
            .build());
        // Object-level read/write/delete under the prefix.
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ))
            .resources(List.of(bucketArn + "/" + prefix + "/*"))
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

    public Role getPyroscopeEksPodRole() {
        return pyroscopeEksPodRole;
    }

    public Role getGrafanaEksPodRole() {
        return grafanaEksPodRole;
    }
}
