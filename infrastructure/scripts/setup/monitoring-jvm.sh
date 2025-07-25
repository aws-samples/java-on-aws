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
      "type": "timeseries",
      "targets": [
        {
          "expr": "jvm_memory_used_bytes{job=\"otel-collector\"}",
          "refId": "A"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
    },
    {
      "id": 3,
      "title": "JVM GC Collections",
      "type": "timeseries",
      "targets": [
        {
          "expr": "rate(jvm_gc_collections_total{job=\"otel-collector\"}[5m])",
          "refId": "A"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
    },
    {
      "id": 4,
      "title": "JVM Heap Memory",
      "type": "timeseries",
      "targets": [
        {
          "expr": "jvm_memory_used_bytes{job=\"otel-collector\",area=\"heap\"}",
          "refId": "A",
          "legendFormat": "Used"
        },
        {
          "expr": "jvm_memory_max_bytes{job=\"otel-collector\",area=\"heap\"}",
          "refId": "B",
          "legendFormat": "Max"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
    }
  ],
  "time": {"from": "now-1h", "to": "now"},
  "refresh": "30s",
  "schemaVersion": 30,
  "version": 1
}
EOF

# Wait for Grafana to be ready before creating dashboard
log "⏳ Waiting for Grafana to be ready for dashboard creation..."
for i in {1..10}; do
  STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database || true)
  if [[ "$STATUS" == "ok" ]]; then
    log "✅ Grafana is ready"
    break
  fi
  log "⏳ ($i/10) Grafana not ready yet..."
  sleep 3
done

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
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF

# Get or create folder first
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

# Create dashboard directly via Grafana API with proper folder placement
log "📊 Creating JVM dashboard in folder '$FOLDER_TITLE'..."

DASHBOARD_PAYLOAD=$(jq -n \
  --argjson dashboard "$(cat "$DASHBOARD_JSON_FILE")" \
  --arg folderUid "$FOLDER_UID" \
  '{
    dashboard: $dashboard,
    folderUid: $folderUid,
    overwrite: true,
    message: "Created JVM Metrics Dashboard via API"
  }')

DASHBOARD_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$DASHBOARD_PAYLOAD" \
  "$GRAFANA_URL/api/dashboards/db")

DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid // empty')

if [[ -n "$DASHBOARD_UID" && "$DASHBOARD_UID" != "null" ]]; then
  log "✅ JVM dashboard created successfully with UID: $DASHBOARD_UID"
  log "📁 Dashboard placed in folder: $FOLDER_TITLE"
else
  log "❌ Failed to create JVM dashboard"
  log "Response: $DASHBOARD_RESPONSE"
  exit 1
fi

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

  # First try POST to create, then PUT to update if it exists
  RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "$CONTACT_POINT_JSON" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points" 2>/dev/null || true)

  # If POST failed, try PUT for update
  if [[ -z "$RESPONSE" ]] || echo "$RESPONSE" | grep -q "error\|failed"; then
    log "🔄 POST failed, trying PUT for update..."
    curl -s -X PUT -H "Content-Type: application/json" \
      -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
      -d "$CONTACT_POINT_JSON" \
      "$GRAFANA_URL/api/v1/provisioning/contact-points/$CONTACT_POINT_UID" 2>/dev/null || true
  fi

  sleep 2

  NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points" | \
    jq -r '.[] | select(.name=="lambda-webhook") | .uid')
fi

if [[ -z "$NOTIF_UID" ]]; then
  log "❌ Failed to create contact point 'lambda-webhook' via API"
  log "🔄 Trying ConfigMap fallback approach..."

  # Create contact point via ConfigMap
  cat > contact-point-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: lambda-webhook-contact-point
  namespace: $NAMESPACE
  labels:
    grafana_notifier: "1"
data:
  contact-point.yaml: |
    apiVersion: 1
    contactPoints:
      - orgId: 1
        name: lambda-webhook
        receivers:
          - uid: lambda-webhook-contact
            type: webhook
            settings:
              url: $LAMBDA_URL
              httpMethod: POST
              username: $WEBHOOK_USER
              password: $WEBHOOK_PASSWORD
              title: "JVM Thread Dump Alert"
              text: "High JVM thread count detected"
EOF

  kubectl apply -f contact-point-configmap.yaml

  # Restart Grafana to pick up the ConfigMap
  log "🔄 Restarting Grafana to apply contact point ConfigMap..."
  kubectl rollout restart deployment grafana -n "$NAMESPACE"
  kubectl rollout status deployment grafana -n "$NAMESPACE" --timeout=120s

  # Wait for Grafana to be ready
  log "⏳ Waiting for Grafana to restart and load contact point..."
  sleep 15

  # Check if contact point is now available
  for i in {1..10}; do
    NOTIF_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
      "$GRAFANA_URL/api/v1/provisioning/contact-points" | \
      jq -r '.[] | select(.name=="lambda-webhook") | .uid' 2>/dev/null || true)

    if [[ -n "$NOTIF_UID" ]]; then
      log "✅ Contact point created via ConfigMap with UID: $NOTIF_UID"
      break
    fi

    log "⏳ Waiting for contact point to be available... ($i/10)"
    sleep 3
  done

  # Clean up temporary file
  rm -f contact-point-configmap.yaml

  if [[ -z "$NOTIF_UID" ]]; then
    log "⚠️ Contact point creation failed via both API and ConfigMap"
    log "⚠️ Continuing with setup, but alerts may not work properly"
    NOTIF_UID="lambda-webhook-contact"  # Use fallback UID for rest of script
  fi
else
  log "✅ Contact point UID: $NOTIF_UID"
fi

# Folder UID is already set from dashboard creation above
# FOLDER_UID is already available from the dashboard creation section

# We already have the dashboard UID from the API creation above
# DASHBOARD_UID is already set from the dashboard creation
if [[ -z "$DASHBOARD_UID" || "$DASHBOARD_UID" == "null" ]]; then
  # Fallback: try to find the dashboard
  DASHBOARD_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/search?query=JVM" | jq -r '.[0].uid // empty')
  if [[ -z "$DASHBOARD_UID" || "$DASHBOARD_UID" == "null" ]]; then
    log "ℹ️ JVM dashboard not found, creating alert rule without dashboard reference"
    DASHBOARD_UID=""
  fi
fi

# Build alert rule JSON with fixed UID for idempotency
log "🛠️ Generating alert rule JSON..."

RULE_UID="jvm-thread-dump-alert"
ALERT_RULE_JSON=$(jq -n \
  --arg url "$LAMBDA_URL" \
  --arg uid "$DASHBOARD_UID" \
  --arg notifUid "$NOTIF_UID" \
  --arg folderUid "$FOLDER_UID" \
  --arg ruleUid "$RULE_UID" '
{
  uid: $ruleUid,
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
        refId: "A",
        intervalMs: 1000,
        maxDataPoints: 43200
      },
      datasourceUid: "promds"
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
} + (if $uid != "" then {dashboardUID: $uid, panelId: 1} else {} end)')

echo "$ALERT_RULE_JSON" > "$LAMBDA_ALERT_RULE_FILE"

log "📤 Creating/updating alert rule (idempotent)..."

RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$ALERT_RULE_JSON" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules/$RULE_UID")

if echo "$RESPONSE" | jq -e '.uid' > /dev/null 2>&1; then
  RETURNED_UID=$(echo "$RESPONSE" | jq -r '.uid')
  log "✅ Alert rule created/updated with UID: $RETURNED_UID"
else
  log "❌ Failed to create/update alert rule via API"
  log "Response: $RESPONSE"
  log "🔄 Trying ConfigMap fallback approach..."

  # Create alert rule via ConfigMap
  cat > alert-rule-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: jvm-alert-rules
  namespace: $NAMESPACE
  labels:
    grafana_alert: "1"
data:
  alert-rules.yaml: |
    apiVersion: 1
    groups:
      - name: lambda-alerts
        orgId: 1
        folder: Unicorn Store Dashboards
        interval: 1m
        rules:
          - uid: jvm-thread-dump-alert
            title: High JVM Threads - Lambda
            condition: B
            data:
              - refId: A
                queryType: ''
                relativeTimeRange:
                  from: 600
                  to: 0
                model:
                  expr: jvm_threads_live_threads{job="otel-collector"}
                  refId: A
                  intervalMs: 1000
                  maxDataPoints: 43200
                datasourceUid: promds
              - refId: B
                queryType: ''
                relativeTimeRange:
                  from: 0
                  to: 0
                model:
                  conditions:
                    - evaluator:
                        params: [80]
                        type: gt
                      operator:
                        type: and
                      query:
                        params: [A]
                      reducer:
                        params: []
                        type: last
                      type: query
                  refId: B
            intervalSeconds: 60
            noDataState: NoData
            execErrState: Alerting
            for: 1m
            annotations:
              summary: High JVM Threads
              description: High number of JVM threads detected. Triggering Lambda thread dump.
              webhookUrl: $LAMBDA_URL
            labels:
              severity: critical
              service: unicorn-store
EOF

  kubectl apply -f alert-rule-configmap.yaml

  # Restart Grafana to pick up the ConfigMap
  log "🔄 Restarting Grafana to apply alert rule ConfigMap..."
  kubectl rollout restart deployment grafana -n "$NAMESPACE"
  kubectl rollout status deployment grafana -n "$NAMESPACE" --timeout=120s

  # Clean up temporary file
  rm -f alert-rule-configmap.yaml

  log "✅ Alert rule created via ConfigMap fallback"
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
