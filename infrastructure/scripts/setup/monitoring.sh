#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

set -x

# --- Configuration ---
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
GRAFANA_USER="admin"

source /etc/profile.d/workshop.sh

# Use IDE_PASSWORD if set; otherwise generate random Grafana password
if [ -z "$IDE_PASSWORD" ]; then
  echo "⚠️  Warning: GRAFANA_PASSWORD is not set via IDE_PASSWORD. A random password will be generated."
  GRAFANA_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"
else
  GRAFANA_PASSWORD="$IDE_PASSWORD"
fi

echo "GRAFANA_PASSWORD is $GRAFANA_PASSWORD"

VALUES_FILE="prometheus-values.yaml"
EXTRA_SCRAPE_FILE="extra-scrape-configs.yaml"
DATASOURCE_FILE="grafana-datasource.yaml"
DASHBOARD_JSON_FILE="jvm-dashboard.json"
DASHBOARD_PROVISIONING_FILE="dashboard-provisioning.yaml"
ALERT_RULE_FILE="grafana-alert-rules.yaml"
GRAFANA_VALUES_FILE="grafana-values.yaml"
LAMBDA_ALERT_RULE_FILE="lambda-alert-rule.json"
NOTIFICATION_POLICY_CONFIGMAP_FILE="notification-policy.yaml"

cleanup() {
  log "🚹 Cleaning up temporary files..."
  rm -f "$VALUES_FILE" "$EXTRA_SCRAPE_FILE" "$DATASOURCE_FILE" "$NOTIFICATION_POLICY_CONFIGMAP_FILE" \
        "$DASHBOARD_JSON_FILE" "$DASHBOARD_PROVISIONING_FILE" \
        "$ALERT_RULE_FILE" "$GRAFANA_VALUES_FILE" "$LAMBDA_ALERT_RULE_FILE"
}
trap cleanup EXIT

# -- Generate secure username and password for webhook
WEBHOOK_USER="grafana-alerts"
WEBHOOK_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')

# -- Create the secret for webhook
aws secretsmanager create-secret \
    --name grafana-webhook-credentials \
    --description "Basic auth credentials for Grafana webhook to Lambda" \
    --secret-string "{\"username\":\"$WEBHOOK_USER\",\"password\":\"$WEBHOOK_PASSWORD\"}"

echo "Webhook credentials created:"
echo "Username: $WEBHOOK_USER"
echo "Password: $WEBHOOK_PASSWORD"
echo "Save these credentials securely!"


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
  extraFlags:
    - web.enable-remote-write-receiver
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
  server:
    http_port: 3000
  log:
    level: debug
  unified_alerting:
    enabled: true
  alerting:
    enabled: false

provisioning:
  enabled: true
  alerting:
    enabled: true
    path: /etc/grafana/provisioning/policies
  dashboards:
    enabled: true
    path: /etc/grafana/provisioning/dashboards
  datasources:
    enabled: true
    path: /etc/grafana/provisioning/datasources
  policy:
    enabled: true

sidecar:
  image:
    repository: kiwigrid/k8s-sidecar
    tag: 1.23.1
  dashboards:
    enabled: true
    label: grafana_dashboard
    folder: /etc/grafana/provisioning/dashboards
    searchNamespace: ALL
  datasources:
    enabled: true
    label: grafana_datasource
    folder: /etc/grafana/provisioning/datasources
    searchNamespace: ALL
  notifiers:
    enabled: true
    label: grafana_notifier
    folder: /etc/grafana/provisioning/notifiers
    searchNamespace: ALL
  policy:
    enabled: true
    label: grafana_policy
    folder: /etc/grafana/provisioning/policies
    searchNamespace: ALL

resources:
  limits:
    cpu: 400m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi
EOF

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

# WICHTIG: Der Keyname muss auf `.yaml` enden, z. B. prometheus-datasource.yaml
kubectl create configmap unicornstore-datasource \
  --from-file=prometheus-datasource.yaml="$DATASOURCE_FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap unicornstore-datasource \
  -n "$NAMESPACE" grafana_datasource=1 --overwrite

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

log "⏳ Waiting for Grafana to become healthy..."
for i in {1..20}; do
  STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database || true)
  if [[ "$STATUS" == "ok" ]]; then
    log "✅ Grafana is healthy"
    break
  fi
  log "⏳ ($i/20) Grafana not ready yet..."
  sleep 5
done

if [[ "$STATUS" != "ok" ]]; then
  log "❌ Grafana did not become healthy in time"
  exit 1
fi

log "🔍 Searching for dashboard with 'JVM' in title..."
DASHBOARD_SEARCH=$(curl --connect-timeout 5 --max-time 10 -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/search?query=JVM")

if [[ -z "$DASHBOARD_SEARCH" ]]; then
  log "❌ Empty response from dashboard search API"
  exit 1
fi

if ! echo "$DASHBOARD_SEARCH" | jq . >/dev/null 2>&1; then
  log "❌ Invalid JSON returned from dashboard search"
  echo "$DASHBOARD_SEARCH"
  exit 1
fi

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

log "🔧 Resolving contact point and folder..."

# Get Contact Point UID
# Check and create contact point if necessary
NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/v1/provisioning/contact-points" | \
  jq -r '.[] | select(.name=="lambda-webhook") | .uid')

if [[ -z "$NOTIF_UID" ]]; then
  log "🔧 Contact point not found, creating..."

  CONTACT_POINT_JSON=$(jq -n \
    --arg name "lambda-webhook" \
    --arg url "$LAMBDA_URL" \
    --arg user "$WEBHOOK_USER" \
    --arg pass "$WEBHOOK_PASSWORD" \
  '{
    name: $name,
    type: "webhook",
    settings: {
      url: $url,
      httpMethod: "POST",
      username: $user,
      password: $pass,
      authorization_scheme: "basic"
    },
    disableResolveMessage: false,
    isDefault: false
  }')


  curl -s -X POST -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "$CONTACT_POINT_JSON" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points"

  sleep 2

  NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points" | \
    jq -r '.[] | select(.name=="lambda-webhook") | .uid')
fi

if [[ -z "$NOTIF_UID" ]]; then
  log "❌ Failed to create contact point 'lambda-webhook'"
  exit 1
else
  log "✅ Contact point UID: $NOTIF_UID"
fi

# Get or create folder
FOLDER_TITLE="Unicorn Store Dashboards"
FOLDER_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/folders" | jq -r --arg title "$FOLDER_TITLE" '.[] | select(.title == $title) | .uid')

if [[ -z "$FOLDER_UID" ]]; then
  log "📁 Folder not found. Creating '$FOLDER_TITLE'..."
  FOLDER_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"title\": \"$FOLDER_TITLE\"}" \
    "$GRAFANA_URL/api/folders" | jq -r '.uid')

  if [[ -z "$FOLDER_UID" ]]; then
    log "❌ Failed to create folder '$FOLDER_TITLE'"
    exit 1
  fi
  log "📁 Folder '$FOLDER_TITLE' created with UID: $FOLDER_UID"
else
  log "📁 Found folder UID: $FOLDER_UID"
fi

# Build alert rule JSON
log "🛠️ Generating alert rule JSON..."

ALERT_RULE_JSON=$(jq -n \
  --arg url "$LAMBDA_URL" \
  --arg uid "$DASHBOARD_UID" \
  --argjson pid "$PANEL_ID" \
  --arg notifUid "$NOTIF_UID" \
  --arg folderUid "$FOLDER_UID" '
{
  dashboardUID: $uid,
  panelId: $pid,
  folderUID: $folderUid,
  ruleGroup: "lambda-alerts",
  title: "High JVM Threads - Lambda",
  condition: "B",
  data: [
    {
      refId: "A",
      relativeTimeRange: { from: 600, to: 0 },
      datasourceUid: "promds",
      model: {
        expr: "sum(jvm_threads_live_threads) by (task_pod_id, cluster_type, cluster, container_name, namespace, container_ip)",
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
    severity: "critical",
    alertname: "High JVM Threads",
    cluster: "{{ $labels.cluster }}",
    cluster_type: "{{ $labels.cluster_type }}",
    container_name: "{{ $labels.container_name }}",
    namespace: "{{ $labels.namespace }}",
    task_pod_id: "{{ $labels.task_pod_id }}",
    container_ip: "{{ $labels.container_ip }}"
  },
  notifications: [
    { uid: $notifUid }
  ]
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

set +x

# --- Final output ---
echo -e "\n✅ Monitoring Stack + Lambda Alert Setup Complete!"
echo "🌍 Grafana URL: http://$GRAFANA_LB"
echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"
echo -e "Grafana URL: http://$GRAFANA_LB\nUsername: $GRAFANA_USER\nPassword: $GRAFANA_PASSWORD" > grafana-credentials.txt
log "💾 Credentials saved to grafana-credentials.txt"

# --- Get Prometheus LoadBalancer Hostname ---
PROM_LB_HOSTNAME=$(kubectl get svc prometheus-server -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)

if [[ -z "$PROM_LB_HOSTNAME" ]]; then
  log "❌ Prometheus Load Balancer Hostname not found"
  exit 1
fi

# Store Prometheus hostname in SSM Parameter Store
PARAM_NAME="/unicornstore/prometheus/internal-dns"
log "📝 Storing Prometheus hostname in SSM Parameter Store..."

# First, put or update the parameter without tags
aws ssm put-parameter \
  --name "$PARAM_NAME" \
  --value "$PROM_LB_HOSTNAME" \
  --type "String" \
  --overwrite \
  --description "Prometheus internal load balancer hostname" \
  --region "$AWS_REGION" \
  --output text

if [ $? -eq 0 ]; then
  # Then, add tags separately
  aws ssm add-tags-to-resource \
    --resource-type "Parameter" \
    --resource-id "$PARAM_NAME" \
    --tags "Key=Project,Value=UnicornStore" "Key=Environment,Value=Development" \
    --region "$AWS_REGION"
    
  log "✅ Successfully stored Prometheus hostname in SSM Parameter Store at $PARAM_NAME"
else
  log "⚠️ Warning: Failed to store Prometheus hostname in SSM Parameter Store"
fi

set -x

# --- Contact Point and Notification Policy for Lambda ---

for i in {1..5}; do
  NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points" \
    | jq -r '.[] | select(.name=="lambda-webhook") | .uid')

  if [[ -n "$NOTIF_UID" ]]; then
    log "✅ Contact Point UID resolved: $NOTIF_UID"
    break
  fi

  log "⏳ Waiting for Contact Point to be available... ($i/5)"
  sleep 2
done

if [[ -z "$NOTIF_UID" ]]; then
  log "❌ Failed to resolve Contact Point UID after creation"
  exit 1
fi

# --- Create and apply notification policy ---
log "🔔 Setting up notification policy for lambda-webhook..."

# Wait for Grafana to be ready
log "⏳ Waiting for Grafana API to be available..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "http://$GRAFANA_LB/api/health" | grep -q "200"; then
    log "✅ Grafana API is available"
    break
  fi
  log "⏳ Waiting for Grafana API... ($i/30)"
  sleep 5
done

# Create notification policy via API
POLICY_JSON=$(cat <<EOF
{
  "receiver": "lambda-webhook",
  "group_by": ["alertname"],
  "routes": [
    {
      "receiver": "lambda-webhook",
      "group_by": ["alertname", "pod"],
      "matchers": [
        "severity = critical"
      ],
      "mute_timings": [],
      "group_wait": "30s",
      "group_interval": "5m",
      "repeat_interval": "4h"
    }
  ],
  "group_wait": "30s",
  "group_interval": "5m",
  "repeat_interval": "1h"
}
EOF
)

# Apply the notification policy
log "📤 Applying notification policy via API..."
POLICY_RESULT=$(curl -s -X PUT -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$POLICY_JSON" \
  "http://$GRAFANA_LB/api/v1/provisioning/policies")

if echo "$POLICY_RESULT" | grep -q "policies updated"; then
  log "✅ Notification policy successfully applied"
else
  log "⚠️ Warning: Notification policy application returned: $POLICY_RESULT"
  
  # Fallback to ConfigMap method if API fails
  log "🔄 Trying fallback method with ConfigMap..."
  cat > "$NOTIFICATION_POLICY_CONFIGMAP_FILE" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: unicornstore-notification-policy
  namespace: $NAMESPACE
  labels:
    grafana_policy: "1"
data:
  notification-policy.yaml: |
    apiVersion: 1
    policies:
      - orgId: 1
        receiver: lambda-webhook
        group_by: ['alertname']
        matchers:
          - alertname = "High JVM Threads"
        routes:
          - receiver: lambda-webhook
            group_by: ['alertname', 'pod']
            matchers:
              - severity = "critical"
            mute_timings: []
            group_wait: 30s
            group_interval: 5m
            repeat_interval: 4h
        continue: false
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 1h
        mute_timings: []
    default_policy:
      receiver: lambda-webhook
      group_by: ['alertname']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 1h
      mute_timings: []
EOF

  kubectl apply -f "$NOTIFICATION_POLICY_CONFIGMAP_FILE"
  log "🔄 Restarting Grafana to apply ConfigMap policy..."
  kubectl rollout restart deployment grafana -n "$NAMESPACE"
  kubectl rollout status deployment grafana -n "$NAMESPACE" --timeout=60s
fi

# Verify policy was applied
log "🔍 Verifying notification policy..."
VERIFY_POLICY=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/v1/provisioning/policies" | jq -r '.receiver')

if [[ "$VERIFY_POLICY" == "lambda-webhook" ]]; then
  log "✅ Notification policy verification successful"
else
  log "⚠️ Warning: Notification policy verification failed, please check manually"
fi

# --- Allow VPC access to Prometheus LoadBalancer on port 9090 ---
log "🔐 Configuring Prometheus ILB Security Group..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" --query "Vpcs[0].VpcId" --output text)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text)

LB_ARN=$(aws elbv2 describe-load-balancers \
  --output json | jq -r \
  --arg dns "$PROM_LB_HOSTNAME" '
    .LoadBalancers[] | select(.DNSName == $dns) | .LoadBalancerArn' \
)

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

set +x

log "✅ Validation complete"
