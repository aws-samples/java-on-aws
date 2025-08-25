#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

NAMESPACE="monitoring"
GRAFANA_USER="admin"
LAMBDA_FUNCTION_NAME="unicornstore-thread-dump-lambda"
SECRET_NAME="unicornstore-ide-password-lambda"
FOLDER_NAME="Unicorn Store Dashboards"
DASHBOARD_TITLE="JVM Metrics - EKS & ECS"
CONTACT_POINT_NAME="lambda-webhook"
ALERT_TITLE="High JVM Threads"
THREAD_THRESHOLD=200

AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

# Build and deploy Lambda
log "🔧 Building Lambda deployment package..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="$SCRIPT_DIR/thread-dump-lambda"
BUILD_DIR="$LAMBDA_DIR/build"
DIST_DIR="$LAMBDA_DIR/dist"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

python3 -m venv "$BUILD_DIR/venv"
source "$BUILD_DIR/venv/bin/activate"
pip install --upgrade pip > /dev/null 2>&1

if [[ -f "$LAMBDA_DIR/requirements.txt" ]]; then
    pip install -r "$LAMBDA_DIR/requirements.txt" -t "$BUILD_DIR/package" > /dev/null 2>&1
fi

cp -r "$LAMBDA_DIR/src/"* "$BUILD_DIR/package/"
cd "$BUILD_DIR/package" && zip -r "$DIST_DIR/lambda_function.zip" . > /dev/null 2>&1

aws lambda update-function-code \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --zip-file fileb://"$DIST_DIR/lambda_function.zip" \
  --no-cli-pager > /dev/null 2>&1

aws lambda wait function-updated --function-name "$LAMBDA_FUNCTION_NAME"

rm -rf "$BUILD_DIR" "$DIST_DIR"
deactivate 2>/dev/null || true

log "✅ Lambda updated"

# Setup Grafana monitoring
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query 'SecretString' --output text)
GRAFANA_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || echo "")
if [[ -z "$GRAFANA_LB" ]]; then
    log "❌ Grafana LoadBalancer not found. Run monitoring.sh first."
    exit 1
fi

GRAFANA_URL="http://$GRAFANA_LB"

log "⏳ Waiting for Grafana..."
for i in {1..20}; do
  STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database 2>/dev/null || true)
  if [[ "$STATUS" == "ok" ]]; then
    break
  fi
  sleep 5
done

API_ID=$(aws apigateway get-rest-apis --query "items[?name=='unicornstore-thread-dump-api'].id" --output text)
VPCE_ID=$(aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=com.amazonaws.${AWS_REGION}.execute-api" --query "VpcEndpoints[0].VpcEndpointId" --output text)
LAMBDA_URL="https://${API_ID}-${VPCE_ID}.execute-api.${AWS_REGION}.vpce.amazonaws.com/prod"

log "📁 Creating folder '$FOLDER_NAME'..."
FOLDER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "{\"title\": \"$FOLDER_NAME\"}" \
  "$GRAFANA_URL/api/folders")

FOLDER_UID=$(echo "$FOLDER_RESPONSE" | jq -r '.uid // empty')
FOLDER_ID=$(echo "$FOLDER_RESPONSE" | jq -r '.id // empty')
if [[ -z "$FOLDER_UID" ]]; then
  # Try to get existing folder
  EXISTING_FOLDER=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders" | jq -r ".[] | select(.title == \"$FOLDER_NAME\")")
  if [[ -n "$EXISTING_FOLDER" ]]; then
    FOLDER_UID=$(echo "$EXISTING_FOLDER" | jq -r '.uid')
    FOLDER_ID=$(echo "$EXISTING_FOLDER" | jq -r '.id')
    log "📁 Using existing folder: $FOLDER_UID"
  else
    FOLDER_UID=""
    FOLDER_ID=0
    log "⚠️ Using General folder"
  fi
else
  log "✅ Folder created: $FOLDER_UID"
fi

log "📊 Creating JVM dashboard..."
cat > /tmp/dashboard.json <<EOF
{
  "id": null,
  "title": "$DASHBOARD_TITLE",
  "tags": ["jvm", "java", "unicorn-store"],
  "timezone": "browser",
  "panels": [
    {
      "id": 1,
      "title": "JVM Thread Count (EKS & ECS)",
      "type": "stat",
      "targets": [
        {
          "expr": "label_replace(jvm_threads_live_threads{job=\"kubernetes-pods\"}, \"short_id\", \"\$1\", \"pod\", \".*-(.{5})\$\") or label_replace(jvm_threads_live_threads{job=\"ecs-unicorn-store-spring\"}, \"short_id\", \"\$1\", \"task_pod_id\", \"(.{8}).*\")",
          "refId": "A",
          "legendFormat": "{{cluster_type}} - {{short_id}}"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "color": {"mode": "thresholds"},
          "thresholds": {
            "steps": [
              {"color": "green", "value": null},
              {"color": "yellow", "value": 50},
              {"color": "red", "value": $THREAD_THRESHOLD}
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
    },
    {
      "id": 2,
      "title": "JVM Memory Usage (EKS & ECS)",
      "type": "timeseries",
      "targets": [
        {
          "expr": "jvm_memory_used_bytes{job=~\"kubernetes-pods|ecs-unicorn-store-spring\"}",
          "refId": "A",
          "legendFormat": "{{cluster_type}} - {{area}} - {{id}}"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
    },
    {
      "id": 3,
      "title": "JVM Thread Count by Platform",
      "type": "timeseries",
      "targets": [
        {
          "expr": "label_replace(jvm_threads_live_threads{job=\"kubernetes-pods\"}, \"short_id\", \"\$1\", \"pod\", \".*-(.{5})\$\") or label_replace(jvm_threads_live_threads{job=\"ecs-unicorn-store-spring\"}, \"short_id\", \"\$1\", \"task_pod_id\", \"(.{8}).*\")",
          "refId": "A",
          "legendFormat": "{{cluster_type}} - {{short_id}}"
        }
      ],
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
    }
  ],
  "time": {"from": "now-1h", "to": "now"},
  "refresh": "30s"
}
EOF

DASHBOARD_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "{\"dashboard\": $(cat /tmp/dashboard.json), \"overwrite\": true, \"folderId\": $FOLDER_ID}" \
  "$GRAFANA_URL/api/dashboards/db")

DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid')
rm /tmp/dashboard.json

log "✅ JVM dashboard created: $DASHBOARD_UID"

log "🚨 Creating contact point with basic auth..."
WEBHOOK_USER="grafana-alerts"
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query 'SecretString' --output text)
WEBHOOK_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

# Check if contact point already exists
EXISTING_CONTACT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points" | jq -r ".[] | select(.name == \"$CONTACT_POINT_NAME\") | .name // empty")

if [[ -z "$EXISTING_CONTACT" ]]; then
  CONTACT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "{
      \"name\": \"$CONTACT_POINT_NAME\",
      \"type\": \"webhook\",
      \"settings\": {
        \"url\": \"$LAMBDA_URL\",
        \"httpMethod\": \"POST\",
        \"username\": \"$WEBHOOK_USER\",
        \"password\": \"$WEBHOOK_PASSWORD\",
        \"authorization_scheme\": \"basic\"
      },
      \"disableResolveMessage\": false
    }" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points")

  # Check if contact point creation was successful
  if echo "$CONTACT_RESPONSE" | jq -e '.name' > /dev/null 2>&1; then
    log "✅ Contact point created"
  else
    log "❌ Contact point creation failed:"
    echo "$CONTACT_RESPONSE" | jq .
  fi
else
  log "✅ Contact point already exists"
fi

log "🚨 Creating alert rule with proper label preservation..."
# Note: Using raw metrics without sum() and by() to preserve all original labels
# This ensures both 'pod' (for EKS) and 'task_pod_id' (for ECS) labels are available
# The Lambda function will process ALL metrics in the valueString, handling multiple
# containers (EKS pods + ECS tasks) in a single alert when they exceed the threshold
ALERT_PAYLOAD="{
  \"title\": \"$ALERT_TITLE\",
  \"condition\": \"B\",
  \"data\": [
    {
      \"refId\": \"A\",
      \"relativeTimeRange\": {\"from\": 600, \"to\": 0},
      \"datasourceUid\": \"promds\",
      \"model\": {
        \"expr\": \"jvm_threads_live_threads{job=~\\\"kubernetes-pods|ecs-unicorn-store-spring\\\"}\",
        \"instant\": true,
        \"refId\": \"A\"
      }
    },
    {
      \"refId\": \"B\",
      \"relativeTimeRange\": {\"from\": 0, \"to\": 0},
      \"datasourceUid\": \"-100\",
      \"model\": {
        \"conditions\": [
          {
            \"evaluator\": {\"params\": [$THREAD_THRESHOLD], \"type\": \"gt\"},
            \"operator\": {\"type\": \"and\"},
            \"query\": {\"params\": [\"A\"]},
            \"reducer\": {\"params\": [], \"type\": \"last\"},
            \"type\": \"query\"
          }
        ],
        \"refId\": \"B\",
        \"type\": \"classic_conditions\"
      }
    }
  ],
  \"intervalSeconds\": 60,
  \"noDataState\": \"NoData\",
  \"execErrState\": \"Alerting\",
  \"for\": \"1m\",
  \"annotations\": {
    \"summary\": \"High JVM Threads\",
    \"description\": \"High number of JVM threads detected. Triggering Lambda thread dump.\",
    \"webhookUrl\": \"$LAMBDA_URL\"
  },
  \"labels\": {
    \"severity\": \"critical\",
    \"alertname\": \"High JVM Threads\",
    \"cluster\": \"{{ \$labels.cluster }}\",
    \"cluster_type\": \"{{ \$labels.cluster_type }}\",
    \"container_name\": \"{{ \$labels.container_name }}\",
    \"namespace\": \"{{ \$labels.namespace }}\",
    \"task_pod_id\": \"{{ \$labels.task_pod_id }}\",
    \"container_ip\": \"{{ \$labels.container_ip }}\"
  }
}"

# Add folderUID if we have one
if [[ -n "$FOLDER_UID" ]]; then
  ALERT_PAYLOAD=$(echo "$ALERT_PAYLOAD" | jq ". + {\"folderUID\": \"$FOLDER_UID\"}")
fi

ALERT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$ALERT_PAYLOAD" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules")

log "✅ Alert rule created"

# Ensure notification policy routes to our contact point
log "🔧 Configuring notification policy..."
POLICY_PAYLOAD="{
  \"receiver\": \"$CONTACT_POINT_NAME\",
  \"group_by\": [\"alertname\"],
  \"group_wait\": \"30s\",
  \"group_interval\": \"5m\",
  \"repeat_interval\": \"1h\"
}"

POLICY_RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$POLICY_PAYLOAD" \
  "$GRAFANA_URL/api/v1/provisioning/policies")

if echo "$POLICY_RESPONSE" | grep -q "policies updated"; then
  log "✅ Notification policy configured"
else
  log "❌ Notification policy configuration failed:"
  echo "$POLICY_RESPONSE"
fi
log "✅ JVM monitoring setup complete"
log "🌍 Grafana: $GRAFANA_URL"
log "📊 Dashboard shows jvm_threads_live_threads from both EKS and ECS"
log "🚨 Alert triggers Lambda thread dump when threads > $THREAD_THRESHOLD, stops when threads < $THREAD_THRESHOLD"
