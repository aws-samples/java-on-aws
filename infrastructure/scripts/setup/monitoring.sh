#!/bin/bash

set -euo pipefail

# 🔧 Configuration
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
DATASOURCE_FILE="grafana-datasource.yaml"
DASHBOARD_JSON_FILE="jvm-dashboard.json"
DASHBOARD_PROVISIONING_FILE="dashboard-provisioning.yaml"
EXTRA_SCRAPE_FILE="extra-scrape-configs.yaml"
VALUES_FILE="prometheus-values.yaml"
ALERT_RULE_FILE="grafana-alert-rules.yaml"

# 🧹 Cleanup function for temporary files
function cleanup() {
  echo "🧹 Cleaning up temporary files..."
  rm -f "$VALUES_FILE" "$DATASOURCE_FILE" "$DASHBOARD_JSON_FILE" "$DASHBOARD_PROVISIONING_FILE" \
        "$EXTRA_SCRAPE_FILE" "$ALERT_RULE_FILE" contact-point.json notification-policy.json \
        grafana-values.yaml alertmanager-config.json prometheus-datasource.json \
        jvm-alert-rule.json test-alert-rule.json lambda-alert-rule.json
}
trap cleanup EXIT

# 🔐 Generate Grafana credentials
GRAFANA_USER="admin"
GRAFANA_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"

# 🗆 Create namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# 🧱 Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# 🔐 Grafana Secret (must be created BEFORE Helm install)
kubectl delete secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
kubectl create secret generic "$GRAFANA_SECRET_NAME" \
  --from-literal=username="$GRAFANA_USER" \
  --from-literal=password="$GRAFANA_PASSWORD" \
  -n "$NAMESPACE"

cat > "$EXTRA_SCRAPE_FILE" <<EOF
- job_name: "otel-collector"
  static_configs:
    - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]

- job_name: "ecs-cloudmap"
  metrics_path: "/actuator/prometheus"
  cloudmap_sd_configs:
    - namespace: "unicornstore.local"
      service: "unicorn-store-spring"
  relabel_configs:
    - source_labels: [__meta_cloudmap_instance_ipv4]
      regex: (.+)
      target_label: __address__
      replacement: "\${1}:9404"
    - source_labels: [__meta_cloudmap_instance_attribute_ECS_CLUSTER_NAME]
      target_label: ecs_cluster
    - source_labels: [__meta_cloudmap_instance_attribute_ECS_SERVICE_NAME]
      target_label: ecs_service
    - source_labels: [__meta_cloudmap_instance_attribute_AVAILABILITY_ZONE]
      target_label: az
    - source_labels: [__meta_cloudmap_instance_attribute_REGION]
      target_label: region
EOF

kubectl create configmap prometheus-extra-scrape --from-file="$EXTRA_SCRAPE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 📂 Prometheus Installation with internal LoadBalancer
echo "📝 Writing temporary $VALUES_FILE"
cat <<EOF > $VALUES_FILE
alertmanager:
  enabled: false

kube-state-metrics:
  enabled: true

prometheus-node-exporter:
  enabled: true

prometheus-pushgateway:
  enabled: false

server:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal

  extraFlags:
    - web.enable-remote-write-receiver

  extraScrapeConfigs: |
    - job_name: "otel-collector"
      static_configs:
        - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]

    - job_name: "ecs-cloudmap"
      metrics_path: "/actuator/prometheus"
      cloudmap_sd_configs:
        - namespace: "unicornstore.local"
          service: "unicorn-store-spring"
      relabel_configs:
        - source_labels: [__meta_cloudmap_instance_ipv4]
          regex: (.+)
          target_label: __address__
          replacement: "\${1}:9404"
        - source_labels: [__meta_cloudmap_instance_attribute_ECS_CLUSTER_NAME]
          target_label: ecs_cluster
        - source_labels: [__meta_cloudmap_instance_attribute_ECS_SERVICE_NAME]
          target_label: ecs_service
        - source_labels: [__meta_cloudmap_instance_attribute_AVAILABILITY_ZONE]
          target_label: az
        - source_labels: [__meta_cloudmap_instance_attribute_REGION]
          target_label: region

  retention: 24h
  persistentVolume:
    size: 25Gi
EOF

echo "🚀 Deploying Prometheus with Helm values"
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

VPC_CIDR=$(aws ec2 describe-vpcs \
--vpc-ids "$VPC_ID" \
--query "Vpcs[0].CidrBlock" \
--output text)

for i in {1..30}; do
  PROM_LB_HOSTNAME=$(kubectl get svc prometheus-server -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "$PROM_LB_HOSTNAME" && "$PROM_LB_HOSTNAME" != "<no value>" ]]; then
    echo "✅ Prometheus ILB ready: $PROM_LB_HOSTNAME"
    aws ssm put-parameter --name "/unicornstore/prometheus/internal-dns" \
      --value "$PROM_LB_HOSTNAME" --type String --overwrite

    echo "🔍 Looking up SG for ILB: $PROM_LB_HOSTNAME"

    # Get Load Balancer ARN by matching its DNS name
    LB_ARN=$(aws elbv2 describe-load-balancers \
      --query "LoadBalancers[?DNSName=='$PROM_LB_HOSTNAME'].LoadBalancerArn" \
      --output text)

    if [[ -z "$LB_ARN" ]]; then
      echo "❌ Could not find Load Balancer ARN for $PROM_LB_HOSTNAME"
      exit 1
    fi

    # Get SG ID from Load Balancer
    ILB_SG_ID=$(aws elbv2 describe-load-balancers \
      --load-balancer-arns "$LB_ARN" \
      --query "LoadBalancers[0].SecurityGroups[0]" \
      --output text)

    if [[ -z "$ILB_SG_ID" || "$ILB_SG_ID" == "None" ]]; then
      echo "❌ Could not determine Security Group for Load Balancer $LB_ARN"
      exit 1
    fi

    echo "🔐 ILB Security Group: $ILB_SG_ID"

    # Authorize Prometheus port for ECS
    aws ec2 authorize-security-group-ingress \
      --group-id "$ILB_SG_ID" \
      --protocol tcp \
      --port 9090 \
      --cidr "$VPC_CIDR" \
      --output text || echo "ℹ️ Rule may already exist"

    break
  fi
  echo "⏳ Waiting for Prometheus ILB... ($i/30)"
  sleep 10
done

# 🗄 Prometheus Datasource
cat > "$DATASOURCE_FILE" <<EOF
apiVersion: 1
datasources:
  - uid: promds
    name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-server.monitoring.svc.cluster.local
    isDefault: true
EOF

kubectl create configmap unicornstore-datasource --from-file="$DATASOURCE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicornstore-datasource -n "$NAMESPACE" grafana_datasource=1 --overwrite

# JVM Dashboard
curl -s -o "$DASHBOARD_JSON_FILE" https://grafana.com/api/dashboards/22108/revisions/3/download

cat > "$DASHBOARD_PROVISIONING_FILE" <<EOF
apiVersion: 1
providers:
  - name: 'unicornstore'
    orgId: 1
    folder: 'Unicorn Store Dashboards'
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
      foldersFromFilesStructure: false
EOF

kubectl create configmap unicornstore-dashboard --from-file="$DASHBOARD_JSON_FILE" --from-file="$DASHBOARD_PROVISIONING_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicornstore-dashboard -n "$NAMESPACE" grafana_dashboard=1 --overwrite

# 📄 Alerting Rule YAML
# 📝 Write alert rule file

cat > "$ALERT_RULE_FILE" <<EOF
apiVersion: 1
groups:
  - orgId: 1
    name: unicornstore-group
    folder: Unicorn Store Dashboards
    interval: 1m
    rules:
      - uid: high-jvm-threads
        title: High JVM Threads
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: promds
            model:
              expr: jvm_threads_live_threads
              datasource:
                type: prometheus
                uid: promds
              format: time_series
              instant: true
              intervalMs: 1000
              maxDataPoints: 43200
              refId: A
          - refId: C
            datasourceUid: "-100"
            model:
              conditions:
                - evaluator:
                    type: gt
                    params: [200]
                  operator:
                    type: and
                  query:
                    params: ["A"]
                  reducer:
                    type: last
                    params: []
                  type: query
              datasource:
                type: __expr__
                uid: "-100"
              expression: A
              intervalMs: 1000
              maxDataPoints: 43200
              refId: C
              type: threshold
        noDataState: NoData
        execErrState: Error
        for: 1m
        labels:
          alert: High JVM Threads
          cluster: "{{ \$labels.cluster }}"
          cluster_type: "{{ \$labels.cluster_type }}"
          container_name: "{{ \$labels.container_name }}"
          namespace: "{{ \$labels.namespace }}"
          task_pod_id: "{{ \$labels.task_pod_id }}"
        annotations:
          summary: "High number of JVM threads"
        isPaused: false
EOF

kubectl create configmap unicornstore-alert-rule \
  --from-file=unicornstore-rule.yaml="$ALERT_RULE_FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap unicornstore-alert-rule -n "$NAMESPACE" grafana_alert=1 --overwrite

# 🔹 Contact Point + Alert Rule via API
export AWS_REGION=$(aws configure get region)
export ALARM_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name unicornstore-stack \
  --query "Stacks[0].Outputs[?starts_with(OutputKey, 'MonitoringAlarmTopic')].OutputValue" \
  --output text)

# Mount it via extraConfigmapMounts in grafana-values.yaml
cat <<EOF > grafana-values.yaml
admin:
  existingSecret: grafana-admin
  userKey: username
  passwordKey: password

persistence:
  enabled: true
  storageClassName: gp3
  size: 10Gi

service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing

grafana.ini:
  unified_alerting:
    enabled: true
  alerting:
    enabled: false # Disable legacy alerting

# Use the correct provisioning structure for Grafana 12.0.x
provisioning:
  enabled: true
  alerting:
    enabled: true
    path: /etc/grafana/provisioning/alerting
  datasources:
    enabled: true
    path: /etc/grafana/provisioning/datasources

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
EOF

helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  --values grafana-values.yaml

# 🔁 Ensure Grafana picks up the new secret
kubectl rollout restart deployment grafana -n "$NAMESPACE"

echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"

# ⏳ LoadBalancer DNS + Login Retry
for i in {1..30}; do
  GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
  if [[ -n "$GRAFANA_LB" && "$GRAFANA_LB" != "<no value>" ]]; then
    echo "🚀 Found LoadBalancer hostname: $GRAFANA_LB"
    for j in {1..30}; do
      if dig +short "$GRAFANA_LB" | grep -qE "^[0-9.]+$"; then
        echo "✅ DNS resolved: http://$GRAFANA_LB"
        for k in {1..10}; do
          if curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" http://$GRAFANA_LB/api/user | grep -q '"id"'; then
            echo "✅ Grafana login successful"
            break 3
          fi
          echo "🔁 Waiting for Grafana to become ready ($k/10)..."
          sleep 10
        done
        echo "❌ Grafana login failed or not ready"
        exit 1
      fi
      echo "🔎 Attempt $j/30: DNS not resolved yet, waiting 5s..."
      sleep 5
    done
  fi
  echo "🔁 Attempt $i/30: LoadBalancer not ready yet, waiting 10s..."
  sleep 10
done

# Create Prometheus data source via API
echo "📊 Creating Prometheus data source via API"
cat <<EOF > prometheus-datasource.json
{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "http://prometheus-server.monitoring.svc.cluster.local",
  "access": "proxy",
  "isDefault": true
}
EOF

curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d @prometheus-datasource.json \
  "http://$GRAFANA_LB/api/datasources" > /dev/null

# Get the data source UID
PROMETHEUS_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/datasources" | jq -r '.[] | select(.type=="prometheus") | .uid')

if [[ -z "$PROMETHEUS_UID" ]]; then
  echo "❌ Failed to create Prometheus data source"
  echo "Trying to use default UID 'promds'"
  PROMETHEUS_UID="promds"
else
  echo "✅ Prometheus data source created with UID: $PROMETHEUS_UID"
fi

# Get the Lambda Function URL for thread dump Lambda
echo "🔍 Getting Lambda Function URL for thread dump Lambda"
LAMBDA_URL=$(aws lambda get-function-url-config --function-name unicornstore-thread-dump-lambda --query 'FunctionUrl' --output text 2>/dev/null || echo "")

if [[ -z "$LAMBDA_URL" ]]; then
  echo "⚠️ Lambda Function URL not found for unicornstore-thread-dump-lambda"
  echo "⚠️ Creating a Function URL for the Lambda function"
  
  # Create Function URL
  URL_RESPONSE=$(aws lambda create-function-url-config \
    --function-name unicornstore-thread-dump-lambda \
    --auth-type NONE 2>&1)
  
  if [[ "$URL_RESPONSE" == *"error"* ]]; then
    echo "❌ Failed to create Lambda Function URL: $URL_RESPONSE"
    echo "⚠️ Will continue without Lambda integration"
  else
    LAMBDA_URL=$(echo "$URL_RESPONSE" | jq -r '.FunctionUrl')
    echo "✅ Created Lambda Function URL: $LAMBDA_URL"
    
    # Add resource-based policy to allow public access
    aws lambda add-permission \
      --function-name unicornstore-thread-dump-lambda \
      --statement-id AllowPublicAccess \
      --action lambda:InvokeFunctionUrl \
      --principal "*" \
      --function-url-auth-type NONE 2>/dev/null || echo "⚠️ Could not add permission to Lambda"
  fi
else
  echo "✅ Found Lambda Function URL: $LAMBDA_URL"
fi

# Create a Lambda-specific alert rule if Lambda URL is available
if [[ -n "$LAMBDA_URL" ]]; then
  echo "📊 Creating Lambda-specific JVM thread alert rule"
  cat <<EOF > lambda-alert-rule.json
{
  "folderUID": "general",
  "ruleGroup": "lambda-alerts",
  "title": "High JVM Threads - Lambda Alert",
  "condition": "B",
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "relativeTimeRange": {
        "from": 600,
        "to": 0
      },
      "datasourceUid": "$PROMETHEUS_UID",
      "model": {
        "expr": "sum(jvm_threads_live_threads) by (pod, cluster_type, cluster, container_name, namespace)",
        "instant": true,
        "intervalMs": 1000,
        "maxDataPoints": 43200,
        "refId": "A"
      }
    },
    {
      "refId": "B",
      "queryType": "",
      "relativeTimeRange": {
        "from": 0,
        "to": 0
      },
      "datasourceUid": "-100",
      "model": {
        "conditions": [
          {
            "evaluator": {
              "params": [
                200
              ],
              "type": "gt"
            },
            "operator": {
              "type": "and"
            },
            "query": {
              "params": [
                "A"
              ]
            },
            "reducer": {
              "params": [],
              "type": "last"
            },
            "type": "query"
          }
        ],
        "refId": "B",
        "type": "classic_conditions"
      }
    }
  ],
  "noDataState": "NoData",
  "execErrState": "Error",
  "for": "1m",
  "annotations": {
    "description": "High number of JVM threads detected, triggering thread dump via Lambda",
    "summary": "High JVM Threads",
    "webhookUrl": "$LAMBDA_URL"
  },
  "labels": {
    "severity": "critical"
  }
}
EOF

  LAMBDA_RULE_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d @lambda-alert-rule.json \
    "http://$GRAFANA_LB/api/v1/provisioning/alert-rules")

  if [[ "$LAMBDA_RULE_RESPONSE" == *"uid"* ]]; then
    echo "✅ Lambda alert rule created successfully"
    LAMBDA_RULE_UID=$(echo "$LAMBDA_RULE_RESPONSE" | jq -r '.uid')
    echo "Lambda alert rule UID: $LAMBDA_RULE_UID"
  else
    echo "❌ Failed to create Lambda alert rule: $LAMBDA_RULE_RESPONSE"
  fi
  
  # Test the Lambda function with a direct webhook call
  echo "🧪 Testing Lambda function with a direct webhook call"
  TEST_PAYLOAD=$(cat <<EOF
{
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "HighJVMThreads",
        "severity": "critical",
        "cluster_type": "eks",
        "cluster": "unicorn-store",
        "task_pod_id": "test-pod",
        "container_name": "unicorn-store-spring",
        "namespace": "unicorn-store-spring"
      },
      "annotations": {
        "summary": "Test High JVM Threads Alert",
        "description": "This is a test alert from Grafana setup script"
      },
      "startsAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "endsAt": "$(date -u -d "+10 minutes" +"%Y-%m-%dT%H:%M:%SZ")"
    }
  ]
}
EOF
)
  
  if [[ -n "$LAMBDA_URL" ]]; then
    LAMBDA_TEST_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
      -d "$TEST_PAYLOAD" \
      "$LAMBDA_URL")
    
    echo "Lambda test response: $LAMBDA_TEST_RESPONSE"
  fi
else
  echo "⚠️ Skipping Lambda alert rule creation as Lambda URL is not available"
fi

echo "Creating JVM thread alert rule via API"
cat <<EOF > jvm-alert-rule.json
{
  "folderUID": "general",
  "ruleGroup": "jvm-alerts",
  "title": "High JVM Threads",
  "condition": "C",
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "relativeTimeRange": {
        "from": 600,
        "to": 0
      },
      "datasourceUid": "$PROMETHEUS_UID",
      "model": {
        "expr": "jvm_threads_live_threads",
        "intervalMs": 1000,
        "maxDataPoints": 43200,
        "refId": "A"
      }
    },
    {
      "refId": "C",
      "queryType": "",
      "relativeTimeRange": {
        "from": 0,
        "to": 0
      },
      "datasourceUid": "-100",
      "model": {
        "conditions": [
          {
            "evaluator": {
              "params": [
                200
              ],
              "type": "gt"
            },
            "operator": {
              "type": "and"
            },
            "query": {
              "params": [
                "A"
              ]
            },
            "reducer": {
              "params": [],
              "type": "last"
            },
            "type": "query"
          }
        ],
        "expression": "",
        "type": "threshold",
        "refId": "C"
      }
    }
  ],
  "noDataState": "NoData",
  "execErrState": "Error",
  "for": "1m",
  "annotations": {
    "description": "JVM thread count is above 200",
    "summary": "High JVM Threads"
  },
  "labels": {
    "severity": "critical"
  }
}
EOF

RULE_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d @jvm-alert-rule.json \
  "http://$GRAFANA_LB/api/v1/provisioning/alert-rules")

if [[ "$RULE_RESPONSE" == *"uid"* ]]; then
  echo "✅ JVM thread alert rule created successfully"
  RULE_UID=$(echo "$RULE_RESPONSE" | jq -r '.uid')
  echo "Alert rule UID: $RULE_UID"
else
  echo "❌ Failed to create JVM thread alert rule: $RULE_RESPONSE"
fi

echo "Creating test alert rule via API"
cat <<EOF > test-alert-rule.json
{
  "folderUID": "general",
  "ruleGroup": "test-alerts",
  "title": "Always Firing Alert",
  "condition": "B",
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "relativeTimeRange": {
        "from": 600,
        "to": 0
      },
      "datasourceUid": "$PROMETHEUS_UID",
      "model": {
        "expr": "vector(1)",
        "intervalMs": 1000,
        "maxDataPoints": 43200,
        "refId": "A"
      }
    },
    {
      "refId": "B",
      "queryType": "",
      "relativeTimeRange": {
        "from": 0,
        "to": 0
      },
      "datasourceUid": "-100",
      "model": {
        "conditions": [
          {
            "evaluator": {
              "params": [
                0
              ],
              "type": "gt"
            },
            "operator": {
              "type": "and"
            },
            "query": {
              "params": [
                "A"
              ]
            },
            "reducer": {
              "params": [],
              "type": "last"
            },
            "type": "query"
          }
        ],
        "expression": "A > 0",
        "type": "math",
        "refId": "B"
      }
    }
  ],
  "noDataState": "NoData",
  "execErrState": "Error",
  "for": "0m",
  "annotations": {
    "description": "This is a test alert that will always fire",
    "summary": "Test Alert"
  },
  "labels": {
    "severity": "critical"
  }
}
EOF

TEST_RULE_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d @test-alert-rule.json \
  "http://$GRAFANA_LB/api/v1/provisioning/alert-rules")

if [[ "$TEST_RULE_RESPONSE" == *"uid"* ]]; then
  echo "✅ Test alert rule created successfully"
  TEST_RULE_UID=$(echo "$TEST_RULE_RESPONSE" | jq -r '.uid')
  echo "Test alert rule UID: $TEST_RULE_UID"
else
  echo "❌ Failed to create test alert rule: $TEST_RULE_RESPONSE"
fi

# Wait for alerts to fire
echo "⏳ Waiting for alerts to fire (30 seconds)..."
sleep 30

# Check if alerts are firing
ALERTS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/alertmanager/grafana/api/v2/alerts")

if [[ "$ALERTS" == "[]" ]]; then
  echo "⚠️ No alerts are currently firing"
else
  echo "✅ Alerts are firing:"
  echo "$ALERTS" | jq .
fi

# Try alternative endpoint for alerts
if [[ "$ALERTS" == "[]" ]]; then
  ALERTS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "http://$GRAFANA_LB/api/v1/alerts")
  
  if [[ "$ALERTS" == "[]" ]]; then
    echo "⚠️ No alerts found on alternative endpoint either"
  else
    echo "✅ Alerts found on alternative endpoint:"
    echo "$ALERTS" | jq .
  fi
fi

# Verify SNS permissions
echo "🔍 Verifying SNS permissions by sending a test message"
SNS_TEST_RESPONSE=$(aws sns publish \
  --topic-arn "$ALARM_TOPIC_ARN" \
  --message "This is a test message from Grafana setup script" \
  --subject "Grafana Setup Test" 2>&1)

if [[ "$SNS_TEST_RESPONSE" == *"error"* ]]; then
  echo "⚠️ SNS permission test failed: $SNS_TEST_RESPONSE"
  echo "You may need to add SNS:Publish permissions to your EKS nodes"
else
  echo "✅ SNS permission test successful"
fi

# Final validation of all components
echo -e "\n📋 Validation Summary:"

# Check Prometheus data source
DATASOURCES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/datasources")

if echo "$DATASOURCES" | jq -e '.[] | select(.type=="prometheus")' > /dev/null; then
  echo "✅ Prometheus data source is configured"
else
  echo "❌ Prometheus data source is missing"
fi

# Check alert rules
ALERT_RULES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/v1/provisioning/alert-rules")

if [[ -n "$ALERT_RULES" && "$ALERT_RULES" != "[]" ]]; then
  echo "✅ Alert rules are configured"
  RULE_COUNT=$(echo "$ALERT_RULES" | jq '. | length')
  echo "   Found $RULE_COUNT alert rules"
else
  echo "❌ No alert rules found"
fi

# Check Alertmanager status
ALERTMANAGER_STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/alertmanager/grafana/api/v2/status")

if [[ -n "$ALERTMANAGER_STATUS" && "$ALERTMANAGER_STATUS" != *"Not found"* ]]; then
  echo "✅ Alertmanager is running"
  
  # Check if our SNS webhook receiver is configured
  if echo "$ALERTMANAGER_STATUS" | jq -e '.config.receivers[] | select(.name=="sns-webhook")' > /dev/null; then
    echo "✅ SNS webhook receiver is configured"
  else
    echo "❌ SNS webhook receiver is not configured"
  fi
else
  echo "❌ Alertmanager status check failed"
fi

# Check if JVM dashboard is available
DASHBOARDS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/search?query=JVM")

if [[ -n "$DASHBOARDS" && "$DASHBOARDS" != "[]" ]]; then
  echo "✅ JVM dashboard is available"
else
  echo "⚠️ JVM dashboard may not be available"
fi

# Check if Lambda integration is working (if configured)
if [[ -n "$LAMBDA_URL" && -n "$LAMBDA_RULE_UID" ]]; then
  echo "✅ Lambda integration is configured"
  echo "   Lambda URL: $LAMBDA_URL"
  echo "   Lambda alert rule UID: $LAMBDA_RULE_UID"
else
  if [[ -n "$LAMBDA_URL" ]]; then
    echo "⚠️ Lambda URL is available but alert rule creation failed"
  else
    echo "⚠️ Lambda integration is not configured"
  fi
fi

# 🔐 Output
echo -e "\n✅ Monitoring Stack Setup Complete!"
echo "🌍 Grafana URL: http://$GRAFANA_LB"
echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"

# Provide instructions for manual verification
echo -e "\n📝 Next Steps:"
echo "1. Open Grafana at http://$GRAFANA_LB"
echo "2. Log in with the credentials above"
echo "3. Navigate to Alerting → Alert rules to verify rules"
echo "4. Navigate to Alerting → Contact points to verify SNS webhook"
echo "5. Navigate to Dashboards to view the JVM dashboard"

if [[ -n "$LAMBDA_URL" ]]; then
  echo "6. Check Lambda function logs to verify webhook integration"
  echo "   aws logs filter-log-events --log-group-name /aws/lambda/unicornstore-thread-dump-lambda"
fi

# Save credentials to a file for reference
echo -e "Grafana URL: http://$GRAFANA_LB\nUsername: $GRAFANA_USER\nPassword: $GRAFANA_PASSWORD" > grafana-credentials.txt
echo "💾 Credentials saved to grafana-credentials.txt"