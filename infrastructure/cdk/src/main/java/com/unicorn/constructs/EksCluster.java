package com.unicorn.constructs;

import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.eks.CfnCluster;
import software.amazon.awscdk.services.eks.CfnCluster.LoggingProperty;
import software.amazon.awscdk.services.eks.CfnCluster.ClusterLoggingProperty;
import software.amazon.awscdk.services.eks.CfnCluster.LoggingTypeConfigProperty;
import software.amazon.awscdk.services.eks.CfnCluster.AccessConfigProperty;
import software.amazon.awscdk.services.eks.CfnCluster.ResourcesVpcConfigProperty;
import software.amazon.awscdk.services.eks.CfnCluster.UpgradePolicyProperty;
import software.amazon.awscdk.services.eks.CfnCluster.ComputeConfigProperty;
import software.amazon.awscdk.services.eks.CfnCluster.KubernetesNetworkConfigProperty;
import software.amazon.awscdk.services.eks.CfnCluster.ElasticLoadBalancingProperty;
import software.amazon.awscdk.services.eks.CfnCluster.StorageConfigProperty;
import software.amazon.awscdk.services.eks.CfnCluster.BlockStorageProperty;
import software.amazon.awscdk.services.eks.CfnAccessEntry;
import software.amazon.awscdk.services.eks.CfnAccessEntry.AccessScopeProperty;
import software.amazon.awscdk.services.eks.CfnAccessEntry.AccessPolicyProperty;
import software.amazon.awscdk.services.eks.CfnPodIdentityAssociation;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.Tags;
import software.constructs.Construct;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public class EksCluster extends Construct {

    private final CfnCluster cluster;
    // private OpenIdConnectProvider provider;

    public EksCluster(final Construct scope, final String id, final String clusterName,
        final String clusterVersion, final IVpc vpc, final ISecurityGroup additionalSG) {
        super(scope, id);

        // Add tags to subnets to enable Load Balancers
        for (ISubnet subnet : vpc.getPublicSubnets()) {
            Tags.of(subnet).add("kubernetes.io/role/elb", "1");
        }
        for (ISubnet subnet : vpc.getPrivateSubnets()) {
            Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1");
        }

        // Create Role for a cluster to allow resource management
        var clusterRole = Role.Builder.create(this, "EKSClusterRole")
            .assumedBy(new ServicePrincipal("eks.amazonaws.com"))
            .roleName(clusterName + "-eks-cluster-role")
            .managedPolicies(Arrays.asList(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSClusterPolicy"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSComputePolicy"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSBlockStoragePolicy"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSLoadBalancingPolicy"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSNetworkingPolicy")
            ))
            .build();
        clusterRole.getAssumeRolePolicy().addStatements(
            PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .principals(Collections.singletonList(
                    new ServicePrincipal("eks.amazonaws.com")
                ))
                .actions(Arrays.asList(
                    "sts:AssumeRole",
                    "sts:TagSession"
                ))
                .build()
        );

        // Create Role for cluster nodes
        var nodeRole = Role.Builder.create(this, "EKSClusterNodeRole")
            .assumedBy(new ServicePrincipal("ec2.amazonaws.com"))
            .roleName(clusterName + "-eks-cluster-node-role")
            .managedPolicies(Arrays.asList(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEKSWorkerNodeMinimalPolicy"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonEC2ContainerRegistryPullOnly")
            ))
            .build();
        clusterRole.getAssumeRolePolicy().addStatements(
            PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .principals(Collections.singletonList(
                    new ServicePrincipal("ec2.amazonaws.com")
                ))
                .actions(Arrays.asList(
                    "sts:AssumeRole"
                ))
                .build()
        );

        // Create EKS cluster
        cluster = CfnCluster.Builder.create(this, "EKSCluster")
            .version(clusterVersion)
            .name(clusterName)
            // Enable EKS Auto Mode
            .computeConfig(ComputeConfigProperty.builder()
                .enabled(true)
                .nodePools(Arrays.asList("system", "general-purpose"))
                .nodeRoleArn(nodeRole.getRoleArn())
                .build())
            // enable the load balancing capability on EKS Auto Mode
            .kubernetesNetworkConfig(KubernetesNetworkConfigProperty.builder()
                .elasticLoadBalancing(ElasticLoadBalancingProperty.builder()
                    .enabled(true)
                    .build())
                .ipFamily("ipv4")
                .build())
            // !!! for EKS Auto Mode we need to enable computeConfig + elasticLoadBalancing + storageConfig
            .storageConfig(StorageConfigProperty.builder()
                .blockStorage(BlockStorageProperty.builder()
                        .enabled(true)
                        .build())
                .build())
            .resourcesVpcConfig(ResourcesVpcConfigProperty.builder()
                    .subnetIds(vpc.selectSubnets(SubnetSelection.builder()
                    .subnetType(SubnetType.PRIVATE_WITH_EGRESS) // deploy cluster nodes in Private subnets
                    .build()).getSubnetIds())
                .endpointPrivateAccess(true)
                .endpointPublicAccess(true)
                .securityGroupIds(List.of(additionalSG.getSecurityGroupId()))
                .build())
            .roleArn(clusterRole.getRoleArn())
            .accessConfig(AccessConfigProperty.builder() // use API mode for cluster access
                .authenticationMode("API")
                .bootstrapClusterCreatorAdminPermissions(true)
                .build())
            .logging(LoggingProperty.builder()
                .clusterLogging(ClusterLoggingProperty.builder()
                    .enabledTypes(List.of(
                        LoggingTypeConfigProperty.builder().type("api").build(),
                        LoggingTypeConfigProperty.builder().type("audit").build(),
                        LoggingTypeConfigProperty.builder().type("authenticator").build(),
                        LoggingTypeConfigProperty.builder().type("controllerManager").build(),
                        LoggingTypeConfigProperty.builder().type("scheduler").build()
                    )).build())
                .build())
            .upgradePolicy(UpgradePolicyProperty.builder()
                .supportType("STANDARD")
                .build())
            .build();

        // String issuerUrl = eksCluster.getAtt("OpenIdConnectIssuerUrl", ResolutionTypeHint.STRING).toString();
        // provider = OpenIdConnectProvider.Builder.create(this, "EkdClusterProvider")
        //      .url(issuerUrl)
        //      .build();
        // provider.getNode().addDependency(eksCluster);
    }

    // public OpenIdConnectProvider getProvider() {
    //     return provider;
    // }

    public CfnCluster getCluster() {
        return cluster;
    }

    public CfnAccessEntry createAccessEntry(final String principalArn, 
        final String clusterName, final String roleName) {
        var accessEntry = CfnAccessEntry.Builder.create(this, "AccessEntry-" + roleName)
            .clusterName(clusterName)
            .principalArn(principalArn)
            .accessPolicies(List.of(AccessPolicyProperty.builder()
                    .accessScope(AccessScopeProperty.builder()
                        .type("cluster")
                        .build())
                    .policyArn("arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy")
                    .build()))
            .build();
        accessEntry.getNode().addDependency(cluster);
        return accessEntry;
    }

    public void createPodIdentity(final String principalArn, final String clusterName, 
        final String namespace, final String serviceAccount) {
        var podIdentityAssociation = CfnPodIdentityAssociation.Builder.create(this, "CfnPodIdentityAssociationESO")
            .clusterName(clusterName)
            .namespace(namespace)
            .roleArn(principalArn)
            .serviceAccount(serviceAccount)
            .build();
        podIdentityAssociation.getNode().addDependency(cluster);
    }

    // Get the default cluster security group
    public String getClusterSecurityGroupId() {
        return cluster.getAttrClusterSecurityGroupId();
    }

    // Get the default cluster security group as ISecurityGroup
    public ISecurityGroup getClusterSecurityGroup() {
        return SecurityGroup.fromSecurityGroupId(
                this,
                "APIClusterSecurityGroup",
                cluster.getAttrClusterSecurityGroupId()
        );
    }
}
