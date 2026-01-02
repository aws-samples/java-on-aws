package sample.com.constructs;

import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.ISecurityGroup;
import software.amazon.awscdk.services.iam.IRole;
import software.amazon.awscdk.services.eks.v2.alpha.Cluster;
import software.amazon.awscdk.services.eks.v2.alpha.KubernetesVersion;
import software.amazon.awscdk.services.eks.v2.alpha.AccessEntry;
import software.amazon.awscdk.services.eks.v2.alpha.AccessEntryType;
import software.amazon.awscdk.services.eks.v2.alpha.AccessPolicy;
import software.amazon.awscdk.services.eks.v2.alpha.IAccessPolicy;
import software.amazon.awscdk.services.eks.v2.alpha.AccessPolicyNameOptions;
import software.amazon.awscdk.services.eks.v2.alpha.AccessScopeType;
import software.amazon.awscdk.services.eks.v2.alpha.Addon;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;

import java.util.List;

import software.constructs.Construct;

public class Eks extends Construct {

    private final Cluster cluster;
    private final Role cloudwatchAgentRole;

    public Eks(final Construct scope, final String id, final EksProps props) {
        super(scope, id);

        String prefix = props.getPrefix();

        // Create EKS cluster with Auto Mode (default)
        Cluster.Builder clusterBuilder = Cluster.Builder.create(this, "Cluster")
            .clusterName(prefix + "-eks")
            .version(KubernetesVersion.V1_34)
            .vpc(props.getVpc());

        // Add security group if provided
        if (props.getIdeInternalSecurityGroup() != null) {
            clusterBuilder.securityGroup(props.getIdeInternalSecurityGroup());
        }

        cluster = clusterBuilder.build();

        // Create CloudWatch Agent Pod Identity role
        cloudwatchAgentRole = createCloudWatchAgentRole(prefix);

        // Add EKS add-ons
        createAddons();

        // Create Access Entries for workshop access
        createAccessEntries(props);
    }

    /**
     * Creates EKS Pod Identity role for CloudWatch Observability add-on.
     * This role is used by the cloudwatch-agent service account to collect
     * metrics, logs, and traces from the cluster.
     */
    private Role createCloudWatchAgentRole(String prefix) {
        ServicePrincipal eksPods = ServicePrincipal.Builder.create("pods.eks.amazonaws.com").build();

        Role role = Role.Builder.create(this, "CloudWatchAgentRole")
            .roleName(prefix + "-eks-cloudwatch-agent-role")
            .assumedBy(eksPods)
            .description("EKS Pod Identity role for CloudWatch Observability add-on")
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy"),
                ManagedPolicy.fromAwsManagedPolicyName("AWSXrayWriteOnlyAccess")
            ))
            .build();

        // Add sts:TagSession for Pod Identity
        role.getAssumeRolePolicy().addStatements(
            PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .principals(List.of(eksPods))
                .actions(List.of("sts:TagSession"))
                .build()
        );

        return role;
    }

    private void createAddons() {
        // AWS Secrets Store CSI Driver
        Addon.Builder.create(this, "SecretsStoreDriver")
            .cluster(cluster)
            .addonName("aws-secrets-store-csi-driver-provider")
            .build();

        // AWS Mountpoint S3 CSI Driver
        Addon.Builder.create(this, "MountpointS3Driver")
            .cluster(cluster)
            .addonName("aws-mountpoint-s3-csi-driver")
            .build();

        // EKS Pod Identity Agent
        Addon.Builder.create(this, "PodIdentityAgent")
            .cluster(cluster)
            .addonName("eks-pod-identity-agent")
            .build();
    }

    private void createAccessEntries(EksProps props) {
        // Create cluster admin access policy
        IAccessPolicy clusterAdminPolicy = AccessPolicy.fromAccessPolicyName(
            "AmazonEKSClusterAdminPolicy",
            AccessPolicyNameOptions.builder()
                .accessScopeType(AccessScopeType.CLUSTER)
                .build()
        );

        // IDE Instance Role Access Entry (if provided)
        // This grants the IDE instance role cluster admin permissions for kubectl access
        if (props.getIdeInstanceRole() != null) {
            AccessEntry.Builder.create(this, "InstanceAccessEntry")
                .cluster(cluster)
                .principal(props.getIdeInstanceRole().getRoleArn())
                .accessEntryType(AccessEntryType.STANDARD)
                .accessPolicies(List.of(clusterAdminPolicy))
                .build();
        }

        // Workshop Studio Participant Role Access Entry
        // This grants the WSParticipantRole cluster admin permissions for local kubectl access
        String accountId = software.amazon.awscdk.Stack.of(this).getAccount();
        String participantRoleArn = "arn:aws:iam::" + accountId + ":role/WSParticipantRole";

        AccessEntry.Builder.create(this, "ParticipantAccessEntry")
            .cluster(cluster)
            .principal(participantRoleArn)
            .accessEntryType(AccessEntryType.STANDARD)
            .accessPolicies(List.of(clusterAdminPolicy))
            .build();
    }

    // Getters
    public Cluster getCluster() {
        return cluster;
    }

    public String getClusterName() {
        return cluster.getClusterName();
    }

    public String getClusterEndpoint() {
        return cluster.getClusterEndpoint();
    }

    public Role getCloudWatchAgentRole() {
        return cloudwatchAgentRole;
    }

    // Props class
    public static class EksProps {
        private final String prefix;
        private final IVpc vpc;
        private final IRole ideInstanceRole;
        private final ISecurityGroup ideInternalSecurityGroup;

        private EksProps(Builder builder) {
            this.prefix = builder.prefix;
            this.vpc = builder.vpc;
            this.ideInstanceRole = builder.ideInstanceRole;
            this.ideInternalSecurityGroup = builder.ideInternalSecurityGroup;
        }

        public static Builder builder() {
            return new Builder();
        }

        public String getPrefix() {
            return prefix;
        }

        public IVpc getVpc() {
            return vpc;
        }

        public IRole getIdeInstanceRole() {
            return ideInstanceRole;
        }

        public ISecurityGroup getIdeInternalSecurityGroup() {
            return ideInternalSecurityGroup;
        }

        public static class Builder {
            private String prefix = "workshop";
            private IVpc vpc;
            private IRole ideInstanceRole;
            private ISecurityGroup ideInternalSecurityGroup;

            public Builder prefix(String prefix) {
                this.prefix = prefix;
                return this;
            }

            public Builder vpc(IVpc vpc) {
                this.vpc = vpc;
                return this;
            }

            public Builder ideInstanceRole(IRole ideInstanceRole) {
                this.ideInstanceRole = ideInstanceRole;
                return this;
            }

            public Builder ideInternalSecurityGroup(ISecurityGroup ideInternalSecurityGroup) {
                this.ideInternalSecurityGroup = ideInternalSecurityGroup;
                return this;
            }

            public EksProps build() {
                if (vpc == null) {
                    throw new IllegalArgumentException("VPC is required");
                }
                return new EksProps(this);
            }
        }
    }
}