package com.unicorn.core;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
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

        prometheusInternalUrl = "http://prometheus-server.monitoring.svc.cluster.local";

        CfnOutput.Builder.create(this, "PrometheusInternalUrl")
                .description("Prometheus internal service URL (for ECS use)")
                .value(prometheusInternalUrl)
                .exportName("PrometheusInternalUrl")
                .build();
    }

    public Topic getAlarmTopic() {
        return alarmTopic;
    }

    public String getPrometheusInternalUrl() {
        return prometheusInternalUrl;
    }
}
