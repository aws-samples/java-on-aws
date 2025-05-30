package com.unicorn.core;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.customresources.Provider;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.amazon.awscdk.services.secretsmanager.Secret;
import software.amazon.awscdk.services.secretsmanager.SecretStringGenerator;
import software.amazon.awscdk.services.sns.Topic;
import software.amazon.awscdk.services.sns.TopicPolicy;
import software.amazon.awscdk.services.sns.subscriptions.LambdaSubscription;
import software.amazon.awscdk.services.eks.CfnCluster;
import software.amazon.awscdk.services.eks.HelmChart;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class MonitoringConstruct extends Construct {

    private final Topic alarmTopic;
    private String prometheusInternalUrl;
    private String grafanaUrl;

    public MonitoringConstruct(Construct scope, String id, IVpc vpc, CfnCluster eksCluster, Function alertHandlerLambda) {
        super(scope, id);

        alarmTopic = Topic.Builder.create(this, "AlarmTopic")
                .topicName("UnicornStoreAlarms")
                .displayName("Unicorn Store Alarms")
                .build();

        TopicPolicy.Builder.create(this, "AlarmTopicPolicy")
                .topics(List.of(alarmTopic))
                .build()
                .getDocument()
                .addStatements(PolicyStatement.Builder.create()
                        .effect(Effect.DENY)
                        .actions(List.of("sns:Publish"))
                        .principals(List.of(new AnyPrincipal()))
                        .resources(List.of(alarmTopic.getTopicArn()))
                        .conditions(Map.of("Bool", Map.of("aws:SecureTransport", "false")))
                        .build());

        alarmTopic.addSubscription(new LambdaSubscription(alertHandlerLambda));

        Secret grafanaAdminSecret = Secret.Builder.create(this, "GrafanaAdminSecret")
                .generateSecretString(SecretStringGenerator.builder()
                        .secretStringTemplate("{\"username\":\"admin\"}")
                        .generateStringKey("password")
                        .excludePunctuation(true)
                        .build())
                .build();

        deployPrometheusHelmChart();
        deployGrafanaHelmChart(grafanaAdminSecret);
        deployPrometheusAlertRules();
        deployAlertManagerConfig();

        prometheusInternalUrl = "http://prometheus-server.monitoring.svc.cluster.local";

        createGrafanaUrlOutput();

        CfnOutput.Builder.create(this, "PrometheusInternalUrl")
                .description("Prometheus internal service URL (for ECS use)")
                .value(prometheusInternalUrl)
                .exportName("PrometheusInternalUrl")
                .build();

        CfnOutput.Builder.create(this, "GrafanaAdminSecretName")
                .description("Grafana admin credentials secret")
                .value(grafanaAdminSecret.getSecretName())
                .exportName("GrafanaAdminSecret")
                .build();
    }

    private void createGrafanaUrlOutput() {
        Function fetchGrafanaDnsLambda = Function.Builder.create(this, "FetchGrafanaDns")
                .runtime(software.amazon.awscdk.services.lambda.Runtime.PYTHON_3_11)
                .handler("index.handler")
                .timeout(Duration.minutes(1))
                .code(Code.fromInline("""
                    import boto3
                    import os

                    def handler(event, context):
                        elb = boto3.client('elbv2')
                        response = elb.describe_load_balancers()
                        for lb in response['LoadBalancers']:
                            if 'grafana' in lb['LoadBalancerName'] and lb['Scheme'] == 'internet-facing':
                                return { 'PhysicalResourceId': lb['DNSName'], 'Data': { 'GrafanaUrl': 'http://' + lb['DNSName'] } }
                        raise Exception('Grafana Load Balancer not found')
                """))
                .initialPolicy(List.of(
                        PolicyStatement.Builder.create()
                                .effect(Effect.ALLOW)
                                .actions(List.of("elasticloadbalancing:DescribeLoadBalancers"))
                                .resources(List.of("*"))
                                .build()
                ))
                .build();

        Provider provider = Provider.Builder.create(this, "GrafanaUrlProvider")
                .onEventHandler(fetchGrafanaDnsLambda)
                .build();

        software.amazon.awscdk.CustomResource resource = software.amazon.awscdk.CustomResource.Builder.create(this, "GrafanaUrlCustom")
                .serviceToken(provider.getServiceToken())
                .build();

        CfnOutput.Builder.create(this, "GrafanaDashboardUrl")
                .description("Grafana public Web UI")
                .value(resource.getAttString("GrafanaUrl"))
                .exportName("GrafanaUrl")
                .build();
    }

    private void deployPrometheusHelmChart() {
        HelmChart.Builder.create(this, "PrometheusHelm")
                .chart("prometheus")
                .repository("https://prometheus-community.github.io/helm-charts")
                .release("prometheus")
                .namespace("monitoring")
                .createNamespace(true)
                .values(Map.of(
                        "server", Map.of(
                                "service", Map.of(
                                        "type", "LoadBalancer",
                                        "annotations", Map.of(
                                                "service.beta.kubernetes.io/aws-load-balancer-internal", "true"
                                        )
                                ),
                                "ingress", Map.of("enabled", false)
                        )
                ))
                .build();
    }

    private void deployGrafanaHelmChart(Secret adminSecret) {
        HelmChart.Builder.create(this, "GrafanaHelm")
                .chart("grafana")
                .repository("https://grafana.github.io/helm-charts")
                .release("grafana")
                .namespace("monitoring")
                .createNamespace(false)
                .values(Map.of(
                        "service", Map.of(
                                "type", "LoadBalancer",
                                "annotations", Map.of(
                                        "service.beta.kubernetes.io/aws-load-balancer-scheme", "internet-facing"
                                )
                        ),
                        "admin", Map.of(
                                "existingSecret", adminSecret.getSecretName(),
                                "userKey", "username",
                                "passwordKey", "password"
                        ),
                        "datasources", Map.of("datasources.yaml", Map.of(
                                "apiVersion", 1,
                                "datasources", List.of(Map.of(
                                        "name", "Prometheus",
                                        "type", "prometheus",
                                        "url", "http://prometheus-server.monitoring.svc.cluster.local",
                                        "access", "proxy",
                                        "isDefault", true
                                ))
                        ))
                ))
                .build();
    }

    private void deployPrometheusAlertRules() {
        HelmChart.Builder.create(this, "PrometheusRuleHelm")
                .chart("prometheus-rule")
                .repository("https://prometheus-community.github.io/helm-charts")
                .release("prometheus-alerts")
                .namespace("monitoring")
                .values(Map.of(
                        "defaultRules", Map.of("enabled", false),
                        "groups", List.of(Map.of(
                                "name", "unicornstore-alerts",
                                "rules", List.of(Map.of(
                                        "alert", "TooManyJavaThreads",
                                        "expr", "jvm_threads_live_threads > 200",
                                        "for", "2m",
                                        "labels", Map.of("severity", "critical"),
                                        "annotations", Map.of(
                                                "summary", "Too many Java threads",
                                                "description", "Number of Java threads is above 200 on {{ $labels.instance }}"
                                        )
                                ))
                        ))
                ))
                .build();
    }

    private void deployAlertManagerConfig() {
        String alertManagerYaml = String.join("\n",
                "global:",
                "  resolve_timeout: 5m",
                "route:",
                "  group_by: ['alertname']",
                "  group_wait: 30s",
                "  group_interval: 5m",
                "  repeat_interval: 12h",
                "  receiver: 'sns'",
                "receivers:",
                "  - name: 'sns'",
                "    sns_configs:",
                "      - topic_arn: " + alarmTopic.getTopicArn() + ",",
                "        send_resolved: true"
        );

        HelmChart.Builder.create(this, "AlertManagerHelm")
                .chart("alertmanager")
                .repository("https://prometheus-community.github.io/helm-charts")
                .release("alertmanager")
                .namespace("monitoring")
                .createNamespace(false)
                .values(Map.of(
                        "config", alertManagerYaml,
                        "service", Map.of(
                                "type", "LoadBalancer",
                                "annotations", Map.of(
                                        "service.beta.kubernetes.io/aws-load-balancer-internal", "true"
                                )
                        )
                ))
                .build();
    }

    public Topic getAlarmTopic() {
        return alarmTopic;
    }

    public String getPrometheusInternalUrl() {
        return prometheusInternalUrl;
    }

    public String getGrafanaUrl() {
        return grafanaUrl;
    }
}
