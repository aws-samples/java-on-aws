#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

NAMESPACE="monitoring"
GRAFANA_USER="admin"
SECRET_NAME="unicornstore-ide-password-lambda"
CONTACT_POINT_NAME="jvm-analysis-webhook"
ALERT_TITLE="High HTTP POST Request Rate"
REQUESTS_THRESHOLD=20

AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

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

# Clean up existing JVM Analysis folders and create new one
log "🧹 Cleaning up existing JVM Analysis folders..."
FOLDERS_RESPONSE=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders")
echo "$FOLDERS_RESPONSE" | jq -r '.[] | select(.title == "JVM Analysis") | .uid' | while read uid; do
  if [[ -n "$uid" ]]; then
    log "🗑️ Emptying and deleting folder: $uid"
    # Delete all alert rules in the folder first
    curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules" | jq -r ".[] | select(.folderUID == \"$uid\") | .uid" | while read rule_uid; do
      curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules/$rule_uid"
    done
    # Now delete the folder
    curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders/$uid"
  fi
done

log "📁 Creating new JVM Analysis folder..."
FOLDER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d '{"title": "JVM Analysis"}' \
  "$GRAFANA_URL/api/folders")

FOLDER_UID=$(echo "$FOLDER_RESPONSE" | jq -r '.uid // empty')
if [[ -z "$FOLDER_UID" ]]; then
  log "❌ Failed to create JVM Analysis folder"
  exit 1
fi
log "✅ JVM Analysis folder UID: $FOLDER_UID"

log "🚨 Creating contact point..."
# Reset notification policy to default first to unlink contact point
curl -s -X PUT -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d '{"receiver": "grafana-default-email"}' \
  "$GRAFANA_URL/api/v1/provisioning/policies" > /dev/null

# Check if contact point already exists and delete it
EXISTING_CONTACTS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points" | jq -r ".[] | select(.name == \"$CONTACT_POINT_NAME\") | .uid")

if [[ -n "$EXISTING_CONTACTS" ]]; then
  log "🗑️ Deleting existing contact points..."
  echo "$EXISTING_CONTACTS" | while read uid; do
    curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points/$uid"
  done
  sleep 2
fi

CONTACT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "{
    \"name\": \"$CONTACT_POINT_NAME\",
    \"type\": \"webhook\",
    \"settings\": {
      \"url\": \"http://jvm-analysis-service.monitoring.svc.cluster.local/webhook\",
      \"httpMethod\": \"POST\"
    },
    \"disableResolveMessage\": true
  }" \
  "$GRAFANA_URL/api/v1/provisioning/contact-points")

if echo "$CONTACT_RESPONSE" | jq -e '.name' > /dev/null 2>&1; then
  log "✅ Contact point created"
else
  log "❌ Contact point creation failed:"
  echo "$CONTACT_RESPONSE" | jq .
fi

log "🚨 Creating alert rule..."
# Check if alert rule already exists and delete it
EXISTING_ALERT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules" | jq -r ".[] | select(.title == \"$ALERT_TITLE\") | .uid // empty")

if [[ -n "$EXISTING_ALERT" ]]; then
  log "🗑️ Deleting existing alert rule..."
  curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules/$EXISTING_ALERT"
fi
ALERT_PAYLOAD="{
  \"title\": \"$ALERT_TITLE\",
  \"condition\": \"A\",
  \"data\": [
    {
      \"refId\": \"A\",
      \"relativeTimeRange\": {\"from\": 60, \"to\": 0},
      \"datasourceUid\": \"promds\",
      \"model\": {
        \"expr\": \"rate(http_server_requests_seconds_count{method=\\\"POST\\\"}[30s]) > $REQUESTS_THRESHOLD\",
        \"instant\": true,
        \"refId\": \"A\"
      }
    }
  ],
  \"intervalSeconds\": 20,
  \"noDataState\": \"OK\",
  \"execErrState\": \"Alerting\",
  \"for\": \"30s\",
  \"ruleGroup\": \"jvm-analysis-group\",
  \"annotations\": {
    \"summary\": \"High HTTP POST Request Rate\",
    \"description\": \"POST rate: {{ \$value }} req/s for pod {{ \$labels.pod }}\"
  },
  \"labels\": {
    \"severity\": \"warning\",
    \"alertname\": \"High HTTP Request Rate\"
  },
  \"folderUID\": \"$FOLDER_UID\"
}"

ALERT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$ALERT_PAYLOAD" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules")

if echo "$ALERT_RESPONSE" | jq -e '.uid' > /dev/null 2>&1; then
  log "✅ Alert rule created"

  # Update rule group interval to 20 seconds
  log "⏱️ Setting evaluation interval to 20s..."
  RULE_UID=$(echo "$ALERT_RESPONSE" | jq -r '.uid')
  GROUP_UPDATE_PAYLOAD="{
    \"title\": \"jvm-analysis-group\",
    \"folderUid\": \"$FOLDER_UID\",
    \"interval\": 20,
    \"rules\": [{
      \"uid\": \"$RULE_UID\",
      \"title\": \"$ALERT_TITLE\",
      \"condition\": \"A\",
      \"data\": [{
        \"refId\": \"A\",
        \"relativeTimeRange\": {\"from\": 60, \"to\": 0},
        \"datasourceUid\": \"promds\",
        \"model\": {
          \"expr\": \"rate(http_server_requests_seconds_count{method=\\\"POST\\\"}[30s]) > $REQUESTS_THRESHOLD\",
          \"instant\": true,
          \"refId\": \"A\"
        }
      }],
      \"noDataState\": \"OK\",
      \"execErrState\": \"Alerting\",
      \"for\": \"30s\",
      \"annotations\": {
        \"summary\": \"High HTTP POST Request Rate\",
        \"description\": \"POST rate: {{ \$value }} req/s for pod {{ \$labels.pod }}\"
      },
      \"labels\": {
        \"severity\": \"warning\",
        \"alertname\": \"High HTTP Request Rate\"
      }
    }]
  }"

  curl -s -X PUT -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "$GROUP_UPDATE_PAYLOAD" \
    "$GRAFANA_URL/api/v1/provisioning/folder/$FOLDER_UID/rule-groups/jvm-analysis-group" > /dev/null

  log "✅ Evaluation interval set to 20s"
else
  log "❌ Alert rule creation failed: $ALERT_RESPONSE"
  exit 1
fi

# Configure notification policy
log "🔧 Configuring notification policy..."
POLICY_PAYLOAD="{
  \"receiver\": \"$CONTACT_POINT_NAME\",
  \"group_by\": [\"alertname\", \"pod\"],
  \"group_wait\": \"10s\",
  \"group_interval\": \"30s\",
  \"repeat_interval\": \"2m\"
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

log "✅ Analysis JVM monitoring setup complete"
log "🌍 Grafana: $GRAFANA_URL"
log "🚨 Alert fires when POST rate > $REQUESTS_THRESHOLD req/s for 20s, evaluates every 20s, uses 30s rate window"
