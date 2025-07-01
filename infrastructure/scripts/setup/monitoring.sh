#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

# --- Configuration ---
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"

VALUES_FILE="prometheus-values.yaml"
EXTRA_SCRAPE_FILE="extra-scrape-configs.yaml"
DATASOURCE_FILE="grafana-datasource.yaml"
DASHBOARD_JSON_FILE="jvm-dashboard.json"
DASHBOARD_PROVISIONING_FILE="dashboard-provisioning.yaml"
ALERT_RULE_FILE="grafana-alert-rules.yaml"
GRAFANA_VALUES_FILE="grafana-values.yaml"
LAMBDA_ALERT_RULE_FILE="lambda-alert-rule.json"

cleanup() {
  log "🚹 Cleaning up temporary files..."
  rm -f "$VALUES_FILE" "$EXTRA_SCRAPE_FILE" "$DATASOURCE_FILE" \
        "$DASHBOARD_JSON_FILE" "$DASHBOARD_PROVISIONING_FILE" \
        "$ALERT_RULE_FILE" "$GRAFANA_VALUES_FILE" "$LAMBDA_ALERT_RULE_FILE"
}
trap cleanup EXIT

# --- Namespace & Helm setup ---
kubectl create namespace "$NAMESPACE" 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# --- Grafana secret ---
kubectl delete secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
kubectl create secret generic "$GRAFANA_SECRET_NAME" \
  --from-literal=username="$GRAFANA_USER" \
  --from-literal=password="$GRAFANA_PASSWORD" \
  -n "$NAMESPACE"

# --- Prometheus extra scrape configs ---
cat > "$EXTRA_SCRAPE_FILE" <<EOF
- job_name: "otel-collector"
  static_configs:
    - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]
EOF

kubectl create configmap prometheus-extra-scrape --from-file="$EXTRA_SCRAPE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- Prometheus values ---
cat > "$VALUES_FILE" <<EOF
alertmanager:
  enabled: false
server:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
  retention: 24h
  extraScrapeConfigs: |
    - job_name: "otel-collector"
      static_configs:
        - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]
EOF

log "🚀 Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

# --- Grafana Helm values ---
cat > "$GRAFANA_VALUES_FILE" <<EOF
admin:
  existingSecret: grafana-admin
  userKey: username
  passwordKey: password
service:
  enabled: true
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
persistence:
  enabled: true
  storageClassName: gp3
  size: 10Gi
grafana.ini:
  unified_alerting:
    enabled: true
  alerting:
    enabled: false
provisioning:
  enabled: true
  datasources:
    enabled: true
    path: /etc/grafana/provisioning/datasources
  dashboards:
    enabled: true
    path: /etc/grafana/provisioning/dashboards
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
sidecar:
  datasources:
    enabled: true
    label: grafana_datasource
    labelValue: "1"
    searchNamespace: ALL
  dashboards:
    enabled: true
    label: grafana_dashboard
    labelValue: "1"
    searchNamespace: ALL
  alerts:
    enabled: true
    label: grafana_alert
    labelValue: "1"
    searchNamespace: ALL
EOF

# --- Alert rule provisioning ---
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
        condition: B
        data:
          - refId: A
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: promds
            model:
              expr: sum(jvm_threads_live_threads) by (pod, cluster_type, cluster, container_name, namespace)
              instant: true
              intervalMs: 1000
              maxDataPoints: 43200
              refId: A
          - refId: B
            relativeTimeRange:
              from: 0
              to: 0
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
              refId: B
              type: classic_conditions
        noDataState: NoData
        execErrState: Error
        for: 1m
        annotations:
          summary: High JVM Threads
          description: High number of JVM threads detected. Triggering Lambda thread dump.
        labels:
          alert: High JVM Threads
          cluster: "{{ \$labels.cluster }}"
          cluster_type: "{{ \$labels.cluster_type }}"
          container_name: "{{ \$labels.container_name }}"
          namespace: "{{ \$labels.namespace }}"
          task_pod_id: "{{ \$labels.task_pod_id }}"
        isPaused: false
EOF

kubectl create configmap unicornstore-alert-rule \
  --from-file="$ALERT_RULE_FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap unicornstore-alert-rule -n "$NAMESPACE" grafana_alert=1 --overwrite

log "🚀 Deploying Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  --values "$GRAFANA_VALUES_FILE"

# --- Wait for Grafana LB ---
for i in {1..30}; do
  GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
  if [[ -n "$GRAFANA_LB" && "$GRAFANA_LB" != "<no value>" ]]; then
    if dig +short "$GRAFANA_LB" | grep -qE "^[0-9.]+$"; then
      log "✅ Grafana LB: http://$GRAFANA_LB"
      break
    fi
  fi
  log "⏳ Waiting for Grafana LB DNS... ($i/30)"
  sleep 10
done

# --- Datasource ConfigMap ---
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

# --- Dashboard ConfigMap ---
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

# --- Lambda Function URL setup ---
LAMBDA_URL=$(aws lambda get-function-url-config --function-name unicornstore-thread-dump-lambda --query 'FunctionUrl' --output text 2>/dev/null || echo "")
if [[ -z "$LAMBDA_URL" ]]; then
  log "Creating Lambda Function URL..."
  LAMBDA_URL=$(aws lambda create-function-url-config --function-name unicornstore-thread-dump-lambda --auth-type NONE --query 'FunctionUrl' --output text)
  aws lambda add-permission \
    --function-name unicornstore-thread-dump-lambda \
    --statement-id AllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --function-url-auth-type NONE || log "⚠️ Permission may already exist"
fi
log "✅ Lambda Function URL: $LAMBDA_URL"

GRAFANA_URL="http://$GRAFANA_LB"

# 1. Search for a dashboard containing "JVM" in the title
log "🔍 Searching for dashboard with 'JVM' in title..."
DASHBOARD_SEARCH=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/search?query=JVM")

DASHBOARD_UID=$(echo "$DASHBOARD_SEARCH" | jq -r '
  .[] |
  select(.title | test("(?i)jvm")) |
  .uid' | head -n1
)

if [[ -z "$DASHBOARD_UID" ]]; then
  log "❌ No dashboard found with title matching 'JVM'"
  exit 1
fi
log "✅ Found dashboard UID: $DASHBOARD_UID"

# 2. Fetch the full dashboard JSON
DASHBOARD_JSON=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID")

# 3. Extract a panel that contains your JVM metric expression
PANEL_ID=$(echo "$DASHBOARD_JSON" | jq -r '
  .dashboard.panels[] |
  select(.targets[]?.expr | test("jvm_threads_live_threads")) |
  .id' | head -n1
)

if [[ -z "$PANEL_ID" ]]; then
  log "❌ No panel found with expression 'jvm_threads_live_threads'"
  exit 1
fi
log "✅ Found panel ID: $PANEL_ID"

# 4. Build the alert rule JSON using the dashboardUID and panelID
ALERT_RULE_JSON=$(jq -n \
  --arg url "$LAMBDA_URL" \
  --arg uid "$DASHBOARD_UID" \
  --argjson pid "$PANEL_ID" '
{
  dashboardUID: $uid,
  panelId: $pid,
  folderUID: "general",
  ruleGroup: "lambda-alerts",
  title: "High JVM Threads - Lambda",
  condition: "B",
  data: [
    {
      refId: "A",
      relativeTimeRange: { from: 600, to: 0 },
      datasourceUid: "promds",
      model: {
        expr: "sum(jvm_threads_live_threads) by (pod, cluster_type, cluster, container_name, namespace)",
        instant: true,
        intervalMs: 1000,
        maxDataPoints: 43200,
        refId: "A"
      }
    },
    {
      refId: "B",
      relativeTimeRange: { from: 0, to: 0 },
      datasourceUid: "-100",
      model: {
        conditions: [
          {
            evaluator: { params: [200], type: "gt" },
            operator: { type: "and" },
            query: { params: ["A"] },
            reducer: { params: [], type: "last" },
            type: "query"
          }
        ],
        refId: "B",
        type: "classic_conditions"
      }
    }
  ],
  noDataState: "NoData",
  execErrState: "Error",
  for: "1m",
  annotations: {
    summary: "High JVM Threads",
    description: "High number of JVM threads detected. Triggering Lambda thread dump.",
    webhookUrl: $url
  },
  labels: {
    severity: "critical"
  }
}
')

# 5. Post the rule via Grafana HTTP API
log "📤 Creating alert rule for dashboard '$DASHBOARD_UID', panel $PANEL_ID..."
RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$ALERT_RULE_JSON" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules")

if echo "$RESPONSE" | jq -e '.uid' > /dev/null; then
  log "✅ Lambda alert rule created: RULE_UID $(echo "$RESPONSE" | jq -r '.uid')"
else
  log "❌ Failed to create Lambda alert rule"
  echo "$RESPONSE"
  exit 1
fi

# --- Final output ---
echo -e "\n✅ Monitoring Stack + Lambda Alert Setup Complete!"
echo "🌍 Grafana URL: http://$GRAFANA_LB"
echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"
echo -e "Grafana URL: http://$GRAFANA_LB\nUsername: $GRAFANA_USER\nPassword: $GRAFANA_PASSWORD" > grafana-credentials.txt
log "💾 Credentials saved to grafana-credentials.txt"


# --- Allow VPC access to Prometheus LoadBalancer on port 9090 ---
log "🔐 Configuring Prometheus ILB Security Group..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" --query "Vpcs[0].VpcId" --output text)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text)

PROM_LB_HOSTNAME=$(kubectl get svc prometheus-server -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || echo "")

LB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='$PROM_LB_HOSTNAME'].LoadBalancerArn" \
  --output text)

if [[ -z "$LB_ARN" ]]; then
  log "❌ Could not find Load Balancer ARN for $PROM_LB_HOSTNAME"
  exit 1
fi

ILB_SG_ID=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$LB_ARN" \
  --query "LoadBalancers[0].SecurityGroups[0]" \
  --output text)

if [[ -z "$ILB_SG_ID" || "$ILB_SG_ID" == "None" ]]; then
  log "❌ Could not determine Security Group for Load Balancer $LB_ARN"
  exit 1
fi

log "🔐 ILB Security Group: $ILB_SG_ID"

aws ec2 authorize-security-group-ingress \
  --group-id "$ILB_SG_ID" \
  --protocol tcp \
  --port 9090 \
  --cidr "$VPC_CIDR" \
  --output text || log "ℹ️ Rule may already exist"

# --- Final validation of Grafana setup ---
log "🔍 Validating Grafana configuration..."

# Validate Prometheus datasource
DATASOURCES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "http://$GRAFANA_LB/api/datasources")
if echo "$DATASOURCES" | jq -e '.[] | select(.type=="prometheus")' > /dev/null; then
  log "✅ Prometheus datasource is configured"
else
  log "❌ Prometheus datasource is missing"
fi

# Validate dashboards
DASHBOARDS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "http://$GRAFANA_LB/api/search?query=JVM")
if [[ -n "$DASHBOARDS" && "$DASHBOARDS" != "[]" ]]; then
  log "✅ JVM dashboard is available"
else
  log "❌ JVM dashboard not found"
fi

# Validate alert rules
ALERT_RULES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "http://$GRAFANA_LB/api/v1/provisioning/alert-rules")
if [[ -n "$ALERT_RULES" && "$ALERT_RULES" != "[]" ]]; then
  log "✅ Alert rules are configured"
  RULE_COUNT=$(echo "$ALERT_RULES" | jq '. | length')
  log "   Found $RULE_COUNT alert rule(s)"
else
  log "❌ No alert rules found"
fi

# Optional: check if Lambda URL is invoked
log "🔍 Test Lambda webhook manually with a mock alert"
curl -s -X POST "$LAMBDA_URL" \
  -H "Content-Type: application/json" \
  -d '{
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
          "summary": "Test Alert",
          "description": "This is a test alert from Grafana setup script"
        },
        "startsAt": "'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'",
        "endsAt": "'"$(date -u -d "+10 minutes" +"%Y-%m-%dT%H:%M:%SZ")"'"
      }
    ]
  }' | jq

log "✅ Validation complete"