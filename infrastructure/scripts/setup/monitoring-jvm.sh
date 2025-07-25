#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

# --- Configuration ---
NAMESPACE="monitoring"
GRAFANA_USER="admin"

# Get password from Secrets Manager
SECRET_NAME="unicornstore-ide-password-lambda"
SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query 'SecretString' \
    --output text)

GRAFANA_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

if [[ -z "$GRAFANA_PASSWORD" || "$GRAFANA_PASSWORD" == "null" ]]; then
    log "❌ Failed to retrieve password from $SECRET_NAME"
    exit 1
fi

# File variables
EXTRA_SCRAPE_FILE="jvm-extra-scrape-configs.yaml"
DASHBOARD_JSON_FILE="jvm-dashboard.json"
DASHBOARD_PROVISIONING_FILE="dashboard-provisioning.yaml"
ALERT_RULE_FILE="grafana-alert-rules.yaml"
LAMBDA_ALERT_RULE_FILE="lambda-alert-rule.json"
NOTIFICATION_POLICY_CONFIGMAP_FILE="notification-policy.yaml"

cleanup() {
  log "🧹 Cleaning up temporary files..."
  rm -f "$EXTRA_SCRAPE_FILE" "$DASHBOARD_JSON_FILE" "$DASHBOARD_PROVISIONING_FILE" \
        "$ALERT_RULE_FILE" "$LAMBDA_ALERT_RULE_FILE" "$NOTIFICATION_POLICY_CONFIGMAP_FILE"
}
trap cleanup EXIT

# Check if monitoring stack exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log "❌ Monitoring namespace not found. Please run monitoring.sh first."
    exit 1
fi

# Get Grafana LoadBalancer URL
GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
if [[ -z "$GRAFANA_LB" ]]; then
    log "❌ Grafana LoadBalancer not found. Please run monitoring.sh first."
    exit 1
fi

GRAFANA_URL="http://$GRAFANA_LB"

# Update Grafana password if we retrieved a different password
if kubectl get secret grafana-admin -n "$NAMESPACE" >/dev/null 2>&1; then
    CURRENT_PASSWORD=$(kubectl get secret grafana-admin -n "$NAMESPACE" -o jsonpath="{.data.password}" | base64 --decode)
    if [[ "$CURRENT_PASSWORD" != "$GRAFANA_PASSWORD" ]]; then
        log "🔄 Updating Grafana password..."
        kubectl create secret generic grafana-admin \
          --from-literal=username="$GRAFANA_USER" \
          --from-literal=password="$GRAFANA_PASSWORD" \
          -n "$NAMESPACE" \
          --dry-run=client -o yaml | kubectl apply -f -

        # Restart Grafana to pick up new password
        kubectl rollout restart deployment grafana -n "$NAMESPACE"
        kubectl rollout status deployment grafana -n "$NAMESPACE" --timeout=60s

        # Wait for Grafana to be ready
        log "⏳ Waiting for Grafana to restart..."
        sleep 10
    fi
fi

echo "Setting up JVM-specific RBAC entries"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-collector
  namespace: unicorn-store-spring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: otel-collector
  namespace: unicorn-store-spring
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: otel-collector
  namespace: unicorn-store-spring
subjects:
  - kind: ServiceAccount
    name: otel-collector
    namespace: unicorn-store-spring
roleRef:
  kind: Role
  name: otel-collector
  apiGroup: rbac.authorization.k8s.io
EOF

# Set webhook credentials
WEBHOOK_USER="grafana-alerts"
WEBHOOK_PASSWORD="$GRAFANA_PASSWORD"

echo "Webhook credentials:"
echo "Username: $WEBHOOK_USER"
echo "Password: $WEBHOOK_PASSWORD"
echo "Save these credentials securely!"

# --- Update Prometheus scrape configs for JVM metrics ---
cat > "$EXTRA_SCRAPE_FILE" <<EOF
- job_name: "otel-collector"
  static_configs:
    - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]
EOF

kubectl create configmap prometheus-extra-scrape --from-file="$EXTRA_SCRAPE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Restart Prometheus to pick up new scrape config
kubectl rollout restart deployment prometheus-server -n "$NAMESPACE"

# --- JVM Dashboard ---
cat > "$DASHBOARD_JSON_FILE" <<EOF
{
  "dashboard": {
    "id": null,
    "title": "JVM Metrics Dashboard",
    "tags": ["jvm", "java", "unicorn-store"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "JVM Thread Count",
        "type": "stat",
        "targets": [
          {
            "expr": "jvm_threads_live_threads{job=\"otel-collector\"}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 50},
                {"color": "red", "value": 100}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "JVM Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "jvm_memory_used_bytes{job=\"otel-collector\"}",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF

cat > "$DASHBOARD_PROVISIONING_FILE" <<EOF
apiVersion: 1
providers:
  - name: 'unicorn-store-dashboards'
    orgId: 1
    folder: 'Unicorn Store Dashboards'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
      foldersFromFilesStructure: false
EOF

kubectl create configmap unicornstore-dashboard --from-file="$DASHBOARD_JSON_FILE" --from-file="$DASHBOARD_PROVISIONING_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicornstore-dashboard -n "$NAMESPACE" grafana_dashboard=1 --overwrite

# --- Lambda Function URL setup ---
# Get Lambda Function URL directly from Lambda service (CDK creates this)
log "📋 Retrieving Lambda Function URL..."
LAMBDA_URL=$(aws lambda get-function-url-config \
    --function-name unicornstore-thread-dump-lambda \
    --query 'FunctionUrl' \
    --output text 2>/dev/null || echo "")

if [[ -z "$LAMBDA_URL" ]]; then
    log "❌ Lambda Function URL not found. Please ensure CDK stack is deployed with Function URL."
    exit 1
fi

log "✅ Lambda Function URL: $LAMBDA_URL"

set -x

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

# --- Contact Point and Notification Policy for Lambda ---
log "🔧 Resolving contact point and folder..."

# Check and create contact point if necessary
NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/v1/provisioning/contact-points" | \
  jq -r '.[] | select(.name=="lambda-webhook") | .uid')

if [[ -z "$NOTIF_UID" ]]; then
  log "🔧 Contact point not found, creating..."

  # Use fixed UID for idempotency
  CONTACT_POINT_UID="lambda-webhook-contact"
  CONTACT_POINT_JSON=$(jq -n \
    --arg name "lambda-webhook" \
    --arg uid "$CONTACT_POINT_UID" \
    --arg url "$LAMBDA_URL" \
    --arg user "$WEBHOOK_USER" \
    --arg pass "$WEBHOOK_PASSWORD" \
  '{
    uid: $uid,
    name: $name,
    type: "webhook",
    settings: {
      url: $url,
      httpMethod: "POST",
      username: $user,
      password: $pass,
      title: "JVM Thread Dump Alert",
      text: "High JVM thread count detected"
    }
  }')

  # Use PUT for idempotent creation/update
  curl -s -X PUT -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "$CONTACT_POINT_JSON" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points/$CONTACT_POINT_UID"

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

  FOLDER_UID=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "{\"title\":\"$FOLDER_TITLE\"}" \
    "$GRAFANA_URL/api/folders" | jq -r '.uid')

  if [[ -z "$FOLDER_UID" || "$FOLDER_UID" == "null" ]]; then
    log "❌ Failed to create folder '$FOLDER_TITLE'"
    exit 1
  fi
  log "📁 Folder '$FOLDER_TITLE' created with UID: $FOLDER_UID"
else
  log "📁 Found folder UID: $FOLDER_UID"
fi

# Get dashboard UID and panel ID
DASHBOARD_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/search?query=JVM" | jq -r '.[0].uid')
PANEL_ID=1

# Build alert rule JSON with fixed UID for idempotency
log "🛠️ Generating alert rule JSON..."

RULE_UID="jvm-thread-dump-alert"
ALERT_RULE_JSON=$(jq -n \
  --arg url "$LAMBDA_URL" \
  --arg uid "$DASHBOARD_UID" \
  --argjson pid "$PANEL_ID" \
  --arg notifUid "$NOTIF_UID" \
  --arg folderUid "$FOLDER_UID" \
  --arg ruleUid "$RULE_UID" '
{
  uid: $ruleUid,
  dashboardUID: $uid,
  panelId: $pid,
  folderUID: $folderUid,
  ruleGroup: "lambda-alerts",
  title: "High JVM Threads - Lambda",
  condition: "B",
  data: [
    {
      refId: "A",
      queryType: "",
      relativeTimeRange: {
        from: 600,
        to: 0
      },
      model: {
        expr: "jvm_threads_live_threads{job=\"otel-collector\"}",
        refId: "A"
      }
    },
    {
      refId: "B",
      queryType: "",
      relativeTimeRange: {
        from: 0,
        to: 0
      },
      model: {
        conditions: [
          {
            evaluator: {
              params: [80],
              type: "gt"
            },
            operator: {
              type: "and"
            },
            query: {
              params: ["A"]
            },
            reducer: {
              params: [],
              type: "last"
            },
            type: "query"
          }
        ],
        refId: "B"
      }
    }
  ],
  intervalSeconds: 60,
  maxDataPoints: 43200,
  noDataState: "NoData",
  execErrState: "Alerting",
  for: "1m",
  annotations: {
    summary: "High JVM Threads",
    description: "High number of JVM threads detected. Triggering Lambda thread dump.",
    webhookUrl: $url
  },
  labels: {
    severity: "critical",
    service: "unicorn-store"
  }
}')

echo "$ALERT_RULE_JSON" > "$LAMBDA_ALERT_RULE_FILE"

log "📤 Creating/updating alert rule (idempotent)..."

RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$ALERT_RULE_JSON" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules/$RULE_UID")

if echo "$RESPONSE" | jq -e '.uid' > /dev/null; then
  RETURNED_UID=$(echo "$RESPONSE" | jq -r '.uid')
  log "✅ Alert rule created/updated with UID: $RETURNED_UID"
else
  log "❌ Failed to create/update alert rule"
  echo "$RESPONSE"
  exit 1
fi

set +x

for i in {1..5}; do
  NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points" \
    | jq -r '.[] | select(.name=="lambda-webhook") | .uid')

  if [[ -n "$NOTIF_UID" ]]; then
    log "✅ Contact Point UID resolved: $NOTIF_UID"
    break
  fi

  log "⏳ Waiting for contact point to be available... ($i/5)"
  sleep 2
done

if [[ -z "$NOTIF_UID" ]]; then
  log "❌ Contact point 'lambda-webhook' not found after creation"
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

# Check current notification policy
log "🔍 Checking current notification policy..."
CURRENT_POLICY=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/v1/provisioning/policies" 2>/dev/null || echo "{}")

CURRENT_RECEIVER=$(echo "$CURRENT_POLICY" | jq -r '.receiver // "default"')

if [[ "$CURRENT_RECEIVER" == "lambda-webhook" ]]; then
  log "✅ Notification policy already configured for lambda-webhook"
else
  log "🔧 Updating notification policy to use lambda-webhook..."
  
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

# --- Final validation of JVM setup ---
log "🔍 Validating JVM monitoring configuration..."

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

# --- Final output ---
echo -e "\n✅ JVM Monitoring + Lambda Alert Setup Complete!"
echo "🌍 Grafana URL: http://$GRAFANA_LB"
echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"
echo "🔗 Lambda Webhook URL: $LAMBDA_URL"

log "✅ JVM monitoring validation complete"
