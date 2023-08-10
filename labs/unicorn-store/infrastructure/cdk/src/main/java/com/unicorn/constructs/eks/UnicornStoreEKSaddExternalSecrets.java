package com.unicorn.constructs.eks;

import com.unicorn.core.InfrastructureStack;

import software.amazon.awscdk.services.eks.Cluster;
import software.amazon.awscdk.services.eks.HelmChart;
import software.amazon.awscdk.services.eks.HelmChartOptions;
import software.amazon.awscdk.services.eks.ServiceAccount;
import software.amazon.awscdk.services.eks.KubernetesManifest;

import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class UnicornStoreEKSaddExternalSecrets extends Construct {

    public UnicornStoreEKSaddExternalSecrets(final Construct scope, final String id,
            InfrastructureStack infrastructureStack, Cluster cluster,
            ServiceAccount appServiceAccount, final String projectName) {
        super(scope, id);

        // Using AWS SecretManager with External Secret Operator
        // Sync password from to k8s secret
        // https://aws.amazon.com/blogs/containers/leverage-aws-secrets-stores-from-eks-fargate-with-external-secrets-operator/

        // Install External Secret Operator
        HelmChart externalSecretChart = cluster.addHelmChart("external-secrets-operator", HelmChartOptions.builder()
                .repository("https://charts.external-secrets.io")
                .chart("external-secrets")
                .release("external-secrets")
                .namespace("external-secrets")
                .createNamespace(true)
                .values(Map.of(
                        "installCRDs", true,
                        "webhook.port", 9443))
                .wait(true)
                .build());

        Map<String, Object> secretStore = Map.of(
                "apiVersion", "external-secrets.io/v1beta1",
                "kind", "SecretStore",
                "metadata", Map.of(
                        "name", projectName + "-secret-store",
                        "namespace", projectName),
                "spec", Map.of(
                        "provider", Map.of(
                                "aws", Map.of(
                                        "service", "SecretsManager",
                                        "region", infrastructureStack.getRegion(),
                                        "auth", Map.of(
                                                "jwt", Map.of(
                                                        "serviceAccountRef", Map.of(
                                                                "name",
                                                                appServiceAccount.getServiceAccountName())))))));
        KubernetesManifest secretStoreManifest = KubernetesManifest.Builder.create(scope,
                projectName + "-manifest-secret-store")
                .cluster(cluster)
                .manifest(List.of(secretStore))
                .build();
        secretStoreManifest.getNode().addDependency(appServiceAccount);
        secretStoreManifest.getNode().addDependency(externalSecretChart);

        Map<String, Object> externalSecret = Map.of(
                "apiVersion", "external-secrets.io/v1beta1",
                "kind", "ExternalSecret",
                "metadata", Map.of(
                        "name", projectName + "-external-secret",
                        "namespace", projectName),
                "spec", Map.of(
                        "refreshInterval", "1h",
                        "secretStoreRef", Map.of(
                                "name", projectName + "-secret-store",
                                "kind", "SecretStore"),
                        "target", Map.of(
                                "name", infrastructureStack.getDatabaseSecretName(),
                                "creationPolicy", "Owner"),
                        "data", List.of(Map.of(
                                "secretKey", infrastructureStack.getDatabaseSecretKey(),
                                "remoteRef", Map.of(
                                        "key", infrastructureStack.getDatabaseSecretName(),
                                        "property", infrastructureStack.getDatabaseSecretKey())))));

        KubernetesManifest externalSecretManifest = KubernetesManifest.Builder.create(scope,
                projectName + "-manifest-external-secret")
                .cluster(cluster)
                .manifest(List.of(externalSecret))
                .build();
        externalSecretManifest.getNode().addDependency(secretStoreManifest);
    }
}
