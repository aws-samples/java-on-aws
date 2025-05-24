package com.unicorn.core;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.services.grafana.CfnWorkspace;
import software.amazon.awscdk.services.iam.*;
import software.amazon.awscdk.services.lambda.*;
import software.constructs.Construct;

import java.util.List;
import java.util.Map;

/**
 * Construct to create and provision Grafana dashboards
 */
public class GrafanaDashboardConstruct extends Construct {

    public GrafanaDashboardConstruct(Construct scope, String id,
                                     CfnWorkspace grafanaWorkspace,
                                     software.amazon.awscdk.services.aps.CfnWorkspace ampWorkspace) {
        super(scope, id);

        // Create a role for the Lambda function
        Role lambdaRole = Role.Builder.create(this, "GrafanaDashboardLambdaRole")
                .assumedBy(new ServicePrincipal("lambda.amazonaws.com"))
                .managedPolicies(List.of(
                        ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
                ))
                .build();

        // Permissions to Grafana workspace
        lambdaRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "grafana:CreateWorkspaceApiKey",
                        "grafana:DescribeWorkspace",
                        "grafana:UpdateDashboard",
                        "grafana:CreateDashboard"
                ))
                .resources(List.of(grafanaWorkspace.getAttrId()))
                .build());

        // Inline Python code for the Lambda
        String lambdaCode = createLambdaCode();

        // Create Lambda function
        Function dashboardProvisionerFunction = Function.Builder.create(this, "GrafanaDashboardProvisioner")
                .runtime(software.amazon.awscdk.services.lambda.Runtime.PYTHON_3_9)
                .handler("index.handler")
                .code(Code.fromInline(lambdaCode))
                .role(lambdaRole)
                .timeout(Duration.seconds(300))
                .environment(Map.of(
                        "GRAFANA_WORKSPACE_ID", grafanaWorkspace.getAttrId(),
                        "AMP_WORKSPACE_ID", ampWorkspace.getAttrWorkspaceId(),
                        "DASHBOARD_JSON", createDashboardJson()
                ))
                .build();

        // Custom resource to trigger the Lambda
        CustomResource.Builder.create(this, "DashboardProvisionerResource")
                .serviceToken(dashboardProvisionerFunction.getFunctionArn())
                .build();

        // Output URL
        CfnOutput.Builder.create(this, "GrafanaDashboardOutput")
                .description("Grafana Dashboard URL")
                .value("https://" + grafanaWorkspace.getAttrEndpoint() + "/d/unicornstore/unicorn-store-dashboard")
                .exportName("GrafanaDashboardUrl")
                .build();
    }

    private String createDashboardJson() {
        return "{" +
                "\\\"title\\\": \\\"Unicorn Store Dashboard\\\"," +
                "\\\"uid\\\": \\\"unicornstore\\\"," +
                "\\\"panels\\\": []" +
                "}";
        // Replace this with your actual dashboard JSON string, escaped properly
    }

    private String createLambdaCode() {
        return """
            import boto3
            import json
            import os
            import time
            import urllib3
            import logging

            logger = logging.getLogger()
            logger.setLevel(logging.INFO)

            http = urllib3.PoolManager()

            def handler(event, context):
                logger.info('Event: %s', json.dumps(event))

                grafana_workspace_id = os.environ['GRAFANA_WORKSPACE_ID']
                amp_workspace_id = os.environ['AMP_WORKSPACE_ID']
                dashboard_json = os.environ['DASHBOARD_JSON']

                grafana_client = boto3.client('grafana')
                workspace = grafana_client.describe_workspace(workspaceId=grafana_workspace_id)
                grafana_endpoint = workspace['workspace']['endpoint']

                api_key_response = grafana_client.create_workspace_api_key(
                    workspaceId=grafana_workspace_id,
                    keyName='dashboard-provisioner-' + str(int(time.time())),
                    keyRole='ADMIN',
                    secondsToLive=900
                )
                api_key = api_key_response['key']

                datasource_payload = {
                    'name': 'AMP',
                    'type': 'prometheus',
                    'access': 'proxy',
                    'url': f'https://aps-workspaces.{os.environ["AWS_REGION"]}.amazonaws.com/workspaces/{amp_workspace_id}/',
                    'jsonData': {
                        'httpMethod': 'GET',
                        'sigV4Auth': True,
                        'sigV4AuthType': 'default',
                        'sigV4Region': os.environ['AWS_REGION']
                    },
                    'isDefault': True
                }

                http.request(
                    'POST',
                    f'https://{grafana_endpoint}/api/datasources',
                    body=json.dumps(datasource_payload),
                    headers={
                        'Content-Type': 'application/json',
                        'Authorization': f'Bearer {api_key}'
                    }
                )

                response = http.request(
                    'GET',
                    f'https://{grafana_endpoint}/api/datasources/name/AMP',
                    headers={
                        'Authorization': f'Bearer {api_key}'
                    }
                )
                datasource_data = json.loads(response.data.decode('utf-8'))
                prometheus_uid = datasource_data['uid']

                dashboard_data = json.loads(dashboard_json.replace('${prometheusUid}', prometheus_uid))

                dashboard_payload = {
                    'dashboard': dashboard_data,
                    'overwrite': True
                }

                http.request(
                    'POST',
                    f'https://{grafana_endpoint}/api/dashboards/db',
                    body=json.dumps(dashboard_payload),
                    headers={
                        'Content-Type': 'application/json',
                        'Authorization': f'Bearer {api_key}'
                    }
                )
                return {'statusCode': 200, 'body': 'Dashboard created'}
        """;
    }
}