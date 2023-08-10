package com.unicorn.constructs.eks;

import com.unicorn.core.InfrastructureStack;

import software.amazon.awscdk.services.eks.Cluster;
import software.amazon.awscdk.services.eks.FargateProfile;
import software.amazon.awscdk.services.eks.FargateProfileOptions;
import software.amazon.awscdk.services.eks.Selector;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Effect;

import software.constructs.Construct;

import java.util.List;
import java.util.Map;

import org.cdk8s.ApiObjectMetadata;
import org.cdk8s.App;
import org.cdk8s.Chart;
import org.cdk8s.plus25.ConfigMap;
import org.cdk8s.plus25.Namespace;

public class UnicornStoreEKSaddFargate extends Construct {

    public UnicornStoreEKSaddFargate(final Construct scope, final String id,
            InfrastructureStack infrastructureStack, Cluster cluster, final String projectName) {
        super(scope, id);

        // EKS on Fargate doesn't support ARM64. Can be used for x86_x64 workloads
        // https://docs.aws.amazon.com/eks/latest/userguide/fargate.html
        FargateProfile fargateProfile = cluster.addFargateProfile(projectName + "-fargate-profile",
                FargateProfileOptions.builder()
                        .selectors(List.of(Selector.builder().namespace("workloads" + "*").build()))
                        .fargateProfileName("workloads" + "-fargate-profile")
                        .vpc(cluster.getVpc())
                        .build());

        // o11y
        // Logging for Fargate
        // https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html
        PolicyStatement executionRolePolicy = PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "logs:CreateLogStream",
                        "logs:CreateLogGroup",
                        "logs:DescribeLogStreams",
                        "logs:PutLogEvents"))
                .resources(List.of("*"))
                .build();

        fargateProfile.getPodExecutionRole().addToPrincipalPolicy(executionRolePolicy);

        String newLine = System.getProperty("line.separator");

        // Implementation of k8s Namespace and ConfigMap using KubernetesManifest CDK
        // contstruct

        // Map<String, Object> o11yNamespace = Map.of(
        // "apiVersion", "v1",
        // "kind", "Namespace",
        // "metadata", Map.of(
        // "name", "aws-observability",
        // "labels", Map.of(
        // "aws-observability", "enabled")));

        // KubernetesManifest o11yManifestNamespace =
        // KubernetesManifest.Builder.create(scope, projectName + "-o11y-manifest-ns")
        // .cluster(cluster)
        // .manifest(List.of(o11yNamespace))
        // .build();

        // o11yManifestConfigMap.getNode().addDependency(o11yManifestNamespace);

        // String newLine = System.getProperty("line.separator");
        // Map<String, Object> o11yConfigMap = Map.of(
        // "apiVersion", "v1",
        // "kind", "ConfigMap",
        // "metadata", Map.of(
        // "name", "aws-logging",
        // "namespace", "aws-observability"),
        // "data", Map.of(
        // "flb_log_cw", "false",
        // "filters.conf", String.join(newLine,
        // "[FILTER]",
        // " Name parser",
        // " Match *",
        // " Key_name log",
        // " Parser crio",
        // "[FILTER]",
        // " Name kubernetes",
        // " Match kube.*",
        // " Merge_Log On",
        // " Keep_Log Off",
        // " Buffer_Size 0",
        // " Kube_Meta_Cache_TTL 300s"),
        // "output.conf", String.join(newLine,
        // "[OUTPUT]",
        // " Name cloudwatch_logs",
        // " Match kube.*",
        // " region " + infrastructureStack.getRegion(),
        // " log_group_name /aws/eks/" + projectName + "/" +
        // fargateProfile.getFargateProfileName(),
        // " log_stream_prefix from-fluent-bit-",
        // " log_retention_days 60",
        // " auto_create_group true"),
        // "parsers.conf", String.join(newLine,
        // "[PARSER]",
        // " Name crio",
        // " Format Regex",
        // " Regex ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>P|F) (?<log>.*)$",
        // " Time_Key time",
        // " Time_Format %Y-%m-%dT%H:%M:%S.%L%z")));

        // KubernetesManifest o11yManifestConfigMap =
        // KubernetesManifest.Builder.create(scope, projectName + "-o11y-manifest-cm")
        // .cluster(cluster)
        // .manifest(List.of(o11yConfigMap))
        // .build();

        // o11yManifestConfigMap.getNode().addDependency(o11yManifestNamespace);

        // Implementation of k8s Namespace and ConfigMap using cdk8s and cdk8s.plus25
        // approach
        App cdk8sApp = new App();
        Chart o11yChart = new Chart(cdk8sApp, "o11y-chart");

        Namespace o11yNamespace = Namespace.Builder.create(o11yChart, "aws-observability")
                .metadata(ApiObjectMetadata.builder()
                        .name("aws-observability")
                        .labels(Map.of(
                                "aws-observability", "enabled"))
                        .build())
                .build();

        ConfigMap o11yConfigMap = ConfigMap.Builder.create(o11yChart, "aws-logging")
                .metadata(ApiObjectMetadata.builder()
                        .name("aws-logging")
                        .namespace("aws-observability")
                        .build())
                .data(Map.of(
                        "flb_log_cw", "false",
                        "filters.conf", String.join(newLine,
                                "[FILTER]",
                                "    Name parser",
                                "    Match *",
                                "    Key_name log",
                                "    Parser crio",
                                "[FILTER]",
                                "    Name kubernetes",
                                "    Match kube.*",
                                "    Merge_Log On",
                                "    Keep_Log Off",
                                "    Buffer_Size 0",
                                "    Kube_Meta_Cache_TTL 300s"),
                        "output.conf", String.join(newLine,
                                "[OUTPUT]",
                                "    Name cloudwatch_logs",
                                "    Match kube.*",
                                "    region " + infrastructureStack.getRegion(),
                                "    log_group_name /aws/eks/" + projectName + "/"
                                        + fargateProfile.getFargateProfileName(),
                                "    log_stream_prefix from-fluent-bit-",
                                "    log_retention_days 60",
                                "    auto_create_group true"),
                        "parsers.conf", String.join(newLine,
                                "[PARSER]",
                                "    Name crio",
                                "    Format Regex",
                                "    Regex ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>P|F) (?<log>.*)$",
                                "    Time_Key    time",
                                "    Time_Format %Y-%m-%dT%H:%M:%S.%L%z")))
                .build();

        o11yConfigMap.getNode().addDependency(o11yNamespace);

        cluster.addCdk8sChart("o11y-chart", o11yChart);
    }
}
