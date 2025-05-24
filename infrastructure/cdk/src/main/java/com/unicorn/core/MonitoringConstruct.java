package com.unicorn.core;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.aps.CfnRuleGroupsNamespace;
import software.amazon.awscdk.services.aps.CfnWorkspace;
import software.amazon.awscdk.services.cloudwatch.Alarm;
import software.amazon.awscdk.services.cloudwatch.ComparisonOperator;
import software.amazon.awscdk.services.cloudwatch.Metric;
import software.amazon.awscdk.services.cloudwatch.TreatMissingData;
import software.amazon.awscdk.services.cloudwatch.actions.SnsAction;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.sns.Topic;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class MonitoringConstruct extends Construct {

    private final CfnWorkspace ampWorkspace;
    private final software.amazon.awscdk.services.grafana.CfnWorkspace grafanaWorkspace;
    private final Topic alarmTopic;

    public MonitoringConstruct(Construct scope, String id, IVpc vpc, Function alertHandlerLambda) {
        super(scope, id);

        alarmTopic = Topic.Builder.create(this, "AlarmTopic")
                .topicName("UnicornStoreAlarms")
                .displayName("Unicorn Store Alarms")
                .build();

        alarmTopic.addSubscription(new software.amazon.awscdk.services.sns.subscriptions.LambdaSubscription(alertHandlerLambda));

        ampWorkspace = CfnWorkspace.Builder.create(this, "AmpWorkspace")
                .alias("unicornstore")
                .build();
        ampWorkspace.applyRemovalPolicy(RemovalPolicy.DESTROY);

        Role grafanaRole = Role.Builder.create(this, "GrafanaRole")
                .assumedBy(new ServicePrincipal("grafana.amazonaws.com"))
                .managedPolicies(List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("AmazonPrometheusQueryAccess"),
                        ManagedPolicy.fromAwsManagedPolicyName("CloudWatchReadOnlyAccess"),
                        ManagedPolicy.fromAwsManagedPolicyName("AWSXrayReadOnlyAccess")
                ))
                .build();

        grafanaWorkspace = software.amazon.awscdk.services.grafana.CfnWorkspace.Builder.create(this, "GrafanaWorkspace")
                .accountAccessType("CURRENT_ACCOUNT")
                .authenticationProviders(List.of("AWS_SSO"))
                .permissionType("SERVICE_MANAGED")
                .roleArn(grafanaRole.getRoleArn())
                .dataSources(List.of("PROMETHEUS", "CLOUDWATCH", "XRAY"))
                .name("unicornstore-grafana")
                .build();

        createAlertManagerCustomResource();
        createPrometheusRulesCustomResource();

        CfnOutput.Builder.create(this, "AmpWorkspaceOutput")
                .description("Amazon Managed Service for Prometheus Workspace ID")
                .value(ampWorkspace.getAttrWorkspaceId())
                .exportName("AmpWorkspaceId")
                .build();

        CfnOutput.Builder.create(this, "GrafanaWorkspaceOutput")
                .description("Amazon Managed Grafana Workspace URL")
                .value("https://" + grafanaWorkspace.getAttrEndpoint())
                .exportName("GrafanaWorkspaceUrl")
                .build();
    }

    private void createPrometheusRulesCustomResource() {
        String inlineLambdaCode = """
            import boto3
            import os
            import json
            import urllib3

            http = urllib3.PoolManager()

            def handler(event, context):
                grafana = boto3.client('grafana')
                amp = boto3.client('aps')

                workspace_id = os.environ['GRAFANA_WORKSPACE_ID']
                workspace = grafana.describe_workspace(workspaceId=workspace_id)
                endpoint = workspace['workspace']['endpoint']

                # Create a 10-day API key
                api_key_response = grafana.create_workspace_api_key(
                    workspaceId=workspace_id,
                    keyName='unicorn-provisioner-key',
                    keyRole='ADMIN',
                    secondsToLive=864000
                )
                api_key = api_key_response['key']

                response = http.request('GET',
                    f'https://{endpoint}/api/datasources/name/AMP',
                    headers={"Authorization": f"Bearer {api_key}"}
                )

                uid = json.loads(response.data.decode('utf-8'))['uid']

                alert_rules = os.environ['ALERT_RULE_TEMPLATE'].replace('${PROMETHEUS_UID}', uid)

                amp.put_rule_groups_namespace(
                    workspaceId=os.environ['AMP_WORKSPACE_ID'],
                    name='unicornstore-rules',
                    data=alert_rules.encode('utf-8')
                )
                return {'statusCode': 200}
        """;

        String alertRuleTemplate = """
            apiVersion: 1
            groups:
              - orgId: 1
                name: eval-group
                folder: unicorn-store-folder
                interval: 1m
                rules:
                  - uid: eemfuwv5gbnk0e
                    title: unicorn-store-alert-rule
                    condition: A
                    data:
                      - refId: A
                        relativeTimeRange:
                          from: 60
                          to: 0
                        datasourceUid: ${PROMETHEUS_UID}
                        model:
                          disableTextWrap: false
                          editorMode: code
                          expr: |
                            sum by (task_pod_id, cluster, cluster_type, container_name, namespace) (
                              jvm_threads_live_threads{task_pod_id!=""}
                            ) > 200
                          fullMetaSearch: false
                          includeNullMetadata: true
                          instant: true
                          intervalMs: 1000
                          legendFormat: __auto
                          maxDataPoints: 43200
                          range: false
                          refId: A
                          useBackend: false
                    noDataState: OK
                    execErrState: Alerting
                    for: 1m
                    annotations: {}
                    labels:
                      cluster: '{{ $labels.cluster }}'
                      cluster_type: '{{ $labels.cluster_type }}'
                      container_name: '{{ $labels.container_name }}'
                      namespace: '{{ $labels.namespace }}'
                      task_pod_id: '{{ $labels.task_pod_id }}'
                    isPaused: false
                    notification_settings:
                      receiver: unicorn-store-admin
        """;

        Function lambda = Function.Builder.create(this, "PutPrometheusRulesLambda")
                .runtime(Runtime.PYTHON_3_11)
                .handler("index.handler")
                .code(Code.fromInline(inlineLambdaCode))
                .environment(Map.of(
                        "GRAFANA_WORKSPACE_ID", grafanaWorkspace.getAttrId(),
                        "AMP_WORKSPACE_ID", ampWorkspace.getAttrWorkspaceId(),
                        "ALERT_RULE_TEMPLATE", alertRuleTemplate
                ))
                .timeout(Duration.minutes(1))
                .initialPolicy(List.of(
                        PolicyStatement.Builder.create()
                                .effect(Effect.ALLOW)
                                .actions(List.of("aps:PutRuleGroupsNamespace", "grafana:DescribeWorkspace", "grafana:CreateWorkspaceApiKey"))
                                .resources(List.of("*"))
                                .build()
                ))
                .build();

        CustomResource.Builder.create(this, "PrometheusRulesConfig")
                .serviceToken(lambda.getFunctionArn())
                .build();
    }

    private void createAlertManagerCustomResource() {
        String inlineLambdaCode = """
            import boto3
            import os

            def handler(event, context):
                amp = boto3.client('aps')
                amp.put_alert_manager_definition(
                    workspaceId=os.environ['WORKSPACE_ID'],
                    data=os.environ['ALERT_MANAGER_YAML'].encode('utf-8')
                )
                return {'statusCode': 200}
        """;

        String alertManagerYaml = """
            alertmanager_config: |
              global:
                resolve_timeout: 5m
              route:
                group_by: ['alertname']
                group_wait: 30s
                group_interval: 5m
                repeat_interval: 12h
                receiver: 'sns'
                routes:
                - match:
                    severity: critical
                  receiver: 'sns'
              receivers:
              - name: 'sns'
                sns_configs:
                - topic_arn: %s
                  send_resolved: true
            """.formatted(alarmTopic.getTopicArn());

        Function lambda = Function.Builder.create(this, "PutAlertManagerLambda")
                .runtime(Runtime.PYTHON_3_11)
                .handler("index.handler")
                .code(Code.fromInline(inlineLambdaCode))
                .environment(Map.of(
                        "WORKSPACE_ID", ampWorkspace.getAttrWorkspaceId(),
                        "ALERT_MANAGER_YAML", alertManagerYaml
                ))
                .timeout(Duration.minutes(1))
                .initialPolicy(List.of(
                        PolicyStatement.Builder.create()
                                .effect(Effect.ALLOW)
                                .actions(List.of("aps:PutAlertManagerDefinition"))
                                .resources(List.of("*"))
                                .build()
                ))
                .build();

        CustomResource.Builder.create(this, "AlertManagerConfig")
                .serviceToken(lambda.getFunctionArn())
                .build();
    }

    public CfnWorkspace getAmpWorkspace() {
        return ampWorkspace;
    }

    public software.amazon.awscdk.services.grafana.CfnWorkspace getGrafanaWorkspace() {
        return grafanaWorkspace;
    }

    public Topic getAlarmTopic() {
        return alarmTopic;
    }
}
