package com.unicorn.constructs;

import com.unicorn.core.InfrastructureStack;
import com.unicorn.constructs.eks.UnicornStoreEKSaddExternalSecrets;
// import com.unicorn.constructs.eks.UnicornStoreEKSaddFargate;
// import com.unicorn.constructs.eks.UnicornStoreEKSaddPipeline;
// import com.unicorn.constructs.eks.UnicornStoreEKSaddApp;

import software.amazon.awscdk.services.eks.Cluster;
import software.amazon.awscdk.services.eks.KubernetesVersion;
import software.amazon.awscdk.services.eks.ClusterLoggingTypes;
import software.amazon.awscdk.services.eks.AlbControllerOptions;
import software.amazon.awscdk.services.eks.NodegroupOptions;
import software.amazon.awscdk.services.eks.ServiceAccount;
import software.amazon.awscdk.services.eks.ServiceAccountOptions;
import software.amazon.awscdk.services.eks.AlbControllerVersion;
import software.amazon.awscdk.services.eks.AwsAuthMapping;
import software.amazon.awscdk.services.eks.CapacityType;
import software.amazon.awscdk.services.eks.KubernetesManifest;
import software.amazon.awscdk.services.eks.EndpointAccess;
import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.SubnetType;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.ec2.SubnetSelection;
import software.amazon.awscdk.services.iam.IRole;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.FromRoleArnOptions;
import software.amazon.awscdk.cdk.lambdalayer.kubectl.v25.KubectlV25Layer;
import software.amazon.awscdk.services.ecr.IRepository;
import software.amazon.awscdk.services.ecr.Repository;

import software.amazon.awscdk.CfnOutputProps;
import software.amazon.awscdk.CfnOutput;

import software.constructs.Construct;

import java.util.List;
import java.util.Arrays;
import java.util.Map;

public class UnicornStoreEKS extends Construct {

    public UnicornStoreEKS(final Construct scope, final String id,
            InfrastructureStack infrastructureStack, final String projectName) {
        super(scope, id);

        // Create the EKS cluster
        var cluster = Cluster.Builder.create(scope, projectName + "-cluster")
                .clusterName(projectName).clusterName(projectName).vpc(infrastructureStack.getVpc())
                .endpointAccess(EndpointAccess.PUBLIC)
                .vpcSubnets(List.of(SubnetSelection.builder()
                        .subnetType(SubnetType.PRIVATE_WITH_EGRESS).build()))
                .clusterLogging(Arrays.asList(ClusterLoggingTypes.API, ClusterLoggingTypes.AUDIT,
                        ClusterLoggingTypes.AUTHENTICATOR, ClusterLoggingTypes.CONTROLLER_MANAGER,
                        ClusterLoggingTypes.SCHEDULER))
                .version(KubernetesVersion.of("1.27"))
                .kubectlLayer(new KubectlV25Layer(scope, projectName + "-cluster-kubectl-layer"))
                .albController(
                        AlbControllerOptions.builder().version(AlbControllerVersion.V2_4_1).build())
                .defaultCapacity(0)
                .defaultCapacityInstance(InstanceType.of(InstanceClass.M5, InstanceSize.LARGE))
                .build();

        // AWS Console role to manage EKS cluster via UI
        IRole adminRole = Role.fromRoleArn(scope, projectName + "-admin-role",
                "arn:aws:iam::" + infrastructureStack.getAccount() + ":role/Admin",
                FromRoleArnOptions.builder().mutable(false).build());
        // Cloud9 EC2 instance role to manage EKS cluster via kubectl
        IRole workshopAdminRole = Role.fromRoleArn(scope, projectName + "-workshop-admin-role",
                "arn:aws:iam::" + infrastructureStack.getAccount() + ":role/java-on-aws-workshop-admin",
                FromRoleArnOptions.builder().mutable(false).build());
        // Workshop Studio role to manage EKS cluster via UI
        IRole workshopStudioRole = Role.fromRoleArn(scope, projectName + "-workshop-studio-role",
                "arn:aws:iam::" + infrastructureStack.getAccount() + ":assumed-role/WSParticipantRole/Participant",
                FromRoleArnOptions.builder().mutable(false).build());

        // Give Admin access to the cluster
        cluster.getAwsAuth().addRoleMapping(adminRole,
                AwsAuthMapping.builder().groups(List.of("system:masters")).build());
        cluster.getAwsAuth().addRoleMapping(workshopAdminRole,
                AwsAuthMapping.builder().groups(List.of("system:masters")).build());
        cluster.getAwsAuth().addRoleMapping(workshopStudioRole,
                AwsAuthMapping.builder().groups(List.of("system:masters")).build());

        // default node group is x86_64 Managed Node Group
        // Application can use
        // nodeSelector:
        // kubernetes.io/arch: "amd64"
        cluster.addNodegroupCapacity("managed-node-group-x64",
                NodegroupOptions.builder().nodegroupName("managed-node-group-x64")
                        .capacityType(CapacityType.ON_DEMAND)
                        .instanceTypes(List.of(new InstanceType("m5.large"))).minSize(0)
                        .desiredSize(2).maxSize(4).build());

        // Additional node group is ARM64
        // Application can use
        // nodeSelector:
        // kubernetes.io/arch: "arm64"
        // cluster.addNodegroupCapacity("managed-node-group-arm64",
        //         NodegroupOptions.builder().nodegroupName("managed-node-group-arm64")
        //                 .capacityType(CapacityType.ON_DEMAND)
        //                 .instanceTypes(List.of(new InstanceType("m6g.large"))).minSize(1)
        //                 .desiredSize(2).maxSize(4).build());

        // EKS on Fargate doesn't support ARM64. Can be used for x86_x64 workloads
        // new UnicornStoreEKSaddFargate(this, projectName + "-fargate-profile",
        // infrastructureStack,
        // cluster, projectName);

        // App namespace
        Map<String, Object> appNamespace = Map.of("apiVersion", "v1", "kind", "Namespace",
                "metadata", Map.of("name", projectName, "labels", Map.of("app", projectName)));

        KubernetesManifest appManifestNamespace =
                KubernetesManifest.Builder.create(scope, projectName + "-app-manifest-ns")
                        .cluster(cluster).manifest(List.of(appNamespace)).build();

        ServiceAccountOptions appServiceAccountOptions =
                ServiceAccountOptions.builder().name(projectName).namespace(projectName).build();
        ServiceAccount appServiceAccount =
                cluster.addServiceAccount(projectName + "-app-sa", appServiceAccountOptions);
        appServiceAccount.getNode().addDependency(appManifestNamespace);

        // Define access rights to AWS infrastructure for Service Account
        infrastructureStack.getEventBridge().grantPutEventsTo(appServiceAccount);
        infrastructureStack.getDatabaseSecret().grantRead(appServiceAccount);

        // Using AWS SecretManager with External Secret Operator
        // Sync password from to k8s secret
        new UnicornStoreEKSaddExternalSecrets(this, projectName + "-external-secrets",
                infrastructureStack, cluster, appServiceAccount, projectName);

        // https://aws.amazon.com/blogs/opensource/migrating-x-ray-tracing-to-aws-distro-for-opentelemetry/
        PolicyStatement AWSOpenTelemetryPolicy = PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of("logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream",
                        "logs:DescribeLogStreams", "logs:DescribeLogGroups",
                        "logs:PutRetentionPolicy", "xray:PutTraceSegments",
                        "xray:PutTelemetryRecords", "xray:GetSamplingRules",
                        "xray:GetSamplingTargets", "xray:GetSamplingStatisticSummaries",
                        "cloudwatch:PutMetricData", "ssm:GetParameters"))
                .resources(List.of("*")).build();
        appServiceAccount.getGrantPrincipal().addToPrincipalPolicy(AWSOpenTelemetryPolicy);

        // Create and deploy App to EKS cluster
        // var appStack = new UnicornStoreEKSaddApp(this, projectName + "-app-manifest",
        // infrastructureStack, cluster, appServiceAccount, projectName);
        // new CfnOutput(scope, "UnicornStoreServiceURL",
        // CfnOutputProps.builder().exportName("UnicornStoreServiceURL")
        // .value("http://" + appStack.getUnicornStoreServiceURL()).build());

        // Add Continuous Deployment pipeline from ECR to EKS using CodeBuild and kubectl
        // using AWS Codepipeline, Codebuild and kubectl
        // new UnicornStoreEKSaddPipeline(this, projectName + "-pipeline",
        // infrastructureStack, cluster, projectName);

        new CfnOutput(scope, "UnicornStoreEksAwsRegion",
                CfnOutputProps.builder().value(infrastructureStack.getRegion()).build());
        new CfnOutput(scope, "UnicornStoreEksDatabaseJDBCConnectionString", CfnOutputProps.builder()
                .value(infrastructureStack.getDatabaseJDBCConnectionString()).build());
        final IRepository ecrRepo =
                Repository.fromRepositoryName(scope, projectName + "-ecr-repo", projectName);
        new CfnOutput(scope, "UnicornStoreEksRepositoryUri",
                CfnOutputProps.builder().value(ecrRepo.getRepositoryUri()).build());
        final String kubeconfigString = "aws eks update-kubeconfig --name " + projectName
                + " --region " + infrastructureStack.getRegion() + " --role-arn "
                + cluster.getKubectlRole().getRoleArn();
        new CfnOutput(scope, "UnicornStoreEksKubeconfig",
                CfnOutputProps.builder().value(kubeconfigString).build());
    }
}
