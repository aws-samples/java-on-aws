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
