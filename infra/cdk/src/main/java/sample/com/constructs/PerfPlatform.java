package sample.com.constructs;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.s3.Bucket;
import software.constructs.Construct;

import java.util.List;

/**
 * PerfPlatform construct for the agentic performance platform (perf-analyzer module).
 * Creates the IAM roles used by the platform components on Amazon EKS:
 *  - perf-analyzer-eks-pod-role     (perf-analyzer Spring Boot service)
 *  - perf-collector-eks-pod-role    (perf-collector DaemonSet)
 *  - perf-optimizer-eks-pod-role    (perf-optimizer MCP server, CON405)
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
    private final Role perfOptimizerEksPodRole;
    private final Role pyroscopeEksPodRole;
    private final Role grafanaEksPodRole;
    private final Role perfOptimizerKbRole;

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
        this.perfOptimizerEksPodRole = createOptimizerEksPodRole();
        this.pyroscopeEksPodRole = createPyroscopeEksPodRole(props);
        this.grafanaEksPodRole = createGrafanaEksPodRole();
        this.perfOptimizerKbRole = createKbExecRole(props);
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
     * perf-optimizer EKS pod role (CON405 / java-on-amazon-eks).
     * Trusts pods.eks.amazonaws.com (Pod Identity).
     * Grants Bedrock model invocation (Converse) via AmazonBedrockLimitedAccess and
     * Knowledge Base retrieval (bedrock:Retrieve / bedrock:RetrieveAndGenerate) so the
     * perf-optimizer MCP server can explain findings and ground on the S3 Vectors KB.
     * No S3 and no ECS: the optimizer stages nothing to S3 and never calls ECS.
     * Read-only against the cluster is enforced by the Kubernetes ClusterRole
     * (get/list/watch only, no write verbs), not by this IAM role.
     */
    private Role createOptimizerEksPodRole() {
        ServicePrincipal podsPrincipal = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "OptimizerEksPodRole")
            .roleName("perf-optimizer-eks-pod-role")
            .assumedBy(podsPrincipal)
            .description("Role for the perf-optimizer EKS pod to invoke Bedrock and retrieve from the Knowledge Base")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess")
            ))
            .build();

        addTagSession(role);
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("bedrock:Retrieve", "bedrock:RetrieveAndGenerate"))
            .resources(List.of("arn:aws:bedrock:" + Stack.of(this).getRegion()
                + ":" + Stack.of(this).getAccount() + ":knowledge-base/*"))
            .build());

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
     * access to CloudWatch metrics and log group discovery so the perf-platform
     * alert rule, Latency Metrics dashboard, and Grafana datasource health
     * check can query AWS successfully. The dashboard reads ALB
     * TargetResponseTime, RequestCount, and HTTPCode_Target_5XX_Count for
     * whichever ALB(s) participants deploy during the workshop.
     */
    private Role createGrafanaEksPodRole() {
        ServicePrincipal podsPrincipal = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "GrafanaEksPodRole")
            .roleName("grafana-eks-pod-role")
            .assumedBy(podsPrincipal)
            .description("Role for Grafana to read CloudWatch metrics for the perf-platform Latency Metrics dashboard and ServiceLatency alert")
            .build();

        addTagSession(role);
        // Standard CloudWatch read-only set used by Grafana's CloudWatch datasource,
        // including log group discovery required by the datasource health check.
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "cloudwatch:GetMetricData",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "cloudwatch:DescribeAlarmsForMetric",
                "cloudwatch:DescribeAlarmHistory",
                "cloudwatch:DescribeAlarms",
                "logs:DescribeLogGroups",
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

    /**
     * perf-optimizer Knowledge Base execution role.
     * Trusts bedrock.amazonaws.com so the Bedrock Knowledge Base can assume it.
     * Created here (not by a workshop script) because the IDE role cannot
     * iam:CreateRole for perf-* names; the optimizer script only passes this role
     * to bedrock:CreateKnowledgeBase. Grants read of the KB source docs staged in
     * the workshop bucket under perf-optimizer/kb/*, full access to the S3 Vectors
     * store (bucket name convention perf-optimizer-*), and invoke on the Titan
     * embedding model. No permissions boundary (CDK-managed role, not script-created).
     */
    private Role createKbExecRole(PerfPlatformProps props) {
        String region = Stack.of(this).getRegion();
        String account = Stack.of(this).getAccount();

        Role role = Role.Builder.create(this, "PerfOptimizerKbRole")
            .roleName("perf-optimizer-kb-role")
            .assumedBy(ServicePrincipal.Builder.create("bedrock.amazonaws.com")
                .conditions(java.util.Map.of(
                    "StringEquals", java.util.Map.of("aws:SourceAccount", account),
                    "ArnLike", java.util.Map.of("aws:SourceArn",
                        "arn:aws:bedrock:" + region + ":" + account + ":knowledge-base/*")
                ))
                .build())
            .description("Execution role assumed by the perf-optimizer Bedrock Knowledge Base (S3 Vectors)")
            .build();

        // Embed KB documents with the Titan v2 text embedding model.
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("bedrock:InvokeModel"))
            .resources(List.of("arn:aws:bedrock:" + region + "::foundation-model/amazon.titan-embed-text-v2:0"))
            .build());

        // S3 Vectors store backing the KB (bucket + indexes).
        role.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("s3vectors:*"))
            .resources(List.of(
                "arn:aws:s3vectors:" + region + ":" + account + ":bucket/perf-optimizer-*",
                "arn:aws:s3vectors:" + region + ":" + account + ":bucket/perf-optimizer-*/*"
            ))
            .build());

        // Read the KB source documents staged in the workshop bucket.
        if (props.getWorkshopBucket() != null) {
            String bucketArn = props.getWorkshopBucket().getBucketArn();
            role.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("s3:ListBucket"))
                .resources(List.of(bucketArn))
                .conditions(java.util.Map.of(
                    "StringLike", java.util.Map.of("s3:prefix",
                        List.of("perf-optimizer/kb/*", "perf-optimizer/kb"))))
                .build());
            role.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("s3:GetObject"))
                .resources(List.of(bucketArn + "/perf-optimizer/kb/*"))
                .build());
        }

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

    public Role getPerfOptimizerEksPodRole() {
        return perfOptimizerEksPodRole;
    }

    public Role getPyroscopeEksPodRole() {
        return pyroscopeEksPodRole;
    }

    public Role getGrafanaEksPodRole() {
        return grafanaEksPodRole;
    }

    public Role getPerfOptimizerKbRole() {
        return perfOptimizerKbRole;
    }
}
