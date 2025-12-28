#!/bin/bash
# =============================================================================
# Consolidated Analysis Setup Script
# Combines Thread Analysis and Profiling Analysis into single script
# Uses shared Grafana folder and unified notification policy
# =============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Source environment variables
source /etc/profile.d/workshop.sh

PREFIX="${PREFIX:-workshop}"
NAMESPACE="monitoring"
GRAFANA_USER="admin"
SECRET_NAME="${PREFIX}-ide-password"
FOLDER_NAME="Workshop Dashboards"

# Thread Analysis config
LAMBDA_FUNCTION_NAME="${PREFIX}-thread-dump-lambda"
THREAD_DASHBOARD_TITLE="JVM Metrics - EKS & ECS"
THREAD_CONTACT_POINT="thread-dump-lambda-webhook"
THREAD_ALERT_TITLE="High JVM Threads"
THREAD_THRESHOLD=200

# Profiling Analysis config
HTTP_DASHBOARD_TITLE="HTTP Metrics"
PROFILING_CONTACT_POINT="ai-jvm-analyzer-webhook"
PROFILING_ALERT_TITLE="High HTTP Rate"
REQUESTS_THRESHOLD=20

# =============================================================================
# SHARED SETUP
# =============================================================================

log_info "Starting consolidated analysis setup..."

# Get Grafana credentials
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query 'SecretString' --output text)
GRAFANA_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || echo "")
if [[ -z "$GRAFANA_LB" ]]; then
    log_error "Grafana LoadBalancer not found. Run monitoring.sh first."
    exit 1
fi

GRAFANA_URL="http://$GRAFANA_LB"

log_info "Waiting for Grafana..."
for i in {1..20}; do
  STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database 2>/dev/null || true)
  if [[ "$STATUS" == "ok" ]]; then
    log_success "Grafana is ready"
    break
  fi
  sleep 5
done

# Create shared folder
log_info "Creating shared folder '$FOLDER_NAME'..."
FOLDER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "{\"title\": \"$FOLDER_NAME\"}" \
  "$GRAFANA_URL/api/folders")

FOLDER_UID=$(echo "$FOLDER_RESPONSE" | jq -r '.uid // empty')
FOLDER_ID=$(echo "$FOLDER_RESPONSE" | jq -r '.id // empty')
if [[ -z "$FOLDER_UID" ]]; then
  EXISTING_FOLDER=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders" | jq -r ".[] | select(.title == \"$FOLDER_NAME\")")
  if [[ -n "$EXISTING_FOLDER" ]]; then
    FOLDER_UID=$(echo "$EXISTING_FOLDER" | jq -r '.uid')
    FOLDER_ID=$(echo "$EXISTING_FOLDER" | jq -r '.id')
    log_info "Using existing folder: $FOLDER_UID"
  else
    FOLDER_UID=""
    FOLDER_ID=0
    log_warning "Using General folder"
  fi
else
  log_success "Folder created: $FOLDER_UID"
fi

# Get Lambda Function URL for thread dump Lambda
FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$LAMBDA_FUNCTION_NAME" --query "FunctionUrl" --output text 2>/dev/null || echo "")
if [[ -z "$FUNCTION_URL" ]]; then
    log_error "Lambda Function URL not found. Ensure CDK stack is deployed."
    exit 1
fi
log_info "Using Lambda Function URL: $FUNCTION_URL"


# =============================================================================
# SECTION 1: THREAD ANALYSIS
# =============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 1: Thread Analysis Setup"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Build and deploy Lambda
log_info "Building Lambda deployment package..."
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
# Use subshell to avoid changing directory in main script
(cd "$BUILD_DIR/package" && zip -r "$DIST_DIR/lambda_function.zip" . > /dev/null 2>&1)

aws lambda update-function-code \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --zip-file fileb://"$DIST_DIR/lambda_function.zip" \
  --no-cli-pager > /dev/null 2>&1

aws lambda wait function-updated --function-name "$LAMBDA_FUNCTION_NAME"

rm -rf "$BUILD_DIR" "$DIST_DIR"
deactivate 2>/dev/null || true

log_success "Lambda updated"

# Create JVM Metrics dashboard
log_info "Creating JVM Metrics dashboard..."
cat > /tmp/jvm-dashboard.json <<EOF
{
  "id": null,
  "title": "$THREAD_DASHBOARD_TITLE",
  "tags": ["jvm", "java", "workshop", "threads"],
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
  -d "{\"dashboard\": $(cat /tmp/jvm-dashboard.json), \"overwrite\": true, \"folderId\": $FOLDER_ID}" \
  "$GRAFANA_URL/api/dashboards/db")

JVM_DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid')
rm /tmp/jvm-dashboard.json
log_success "JVM Metrics dashboard created: $JVM_DASHBOARD_UID"

# Create thread analysis contact point
log_info "Creating thread analysis contact point..."
WEBHOOK_USER="grafana-alerts"

# Delete old contact point if exists (renamed from lambda-webhook)
OLD_CONTACT_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points" | jq -r '.[] | select(.name == "lambda-webhook") | .uid // empty')
if [[ -n "$OLD_CONTACT_UID" ]]; then
  log_info "Deleting old lambda-webhook contact point..."
  curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points/$OLD_CONTACT_UID"
fi

EXISTING_THREAD_CONTACT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points" | jq -r ".[] | select(.name == \"$THREAD_CONTACT_POINT\") | .name // empty")

if [[ -z "$EXISTING_THREAD_CONTACT" ]]; then
  CONTACT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "{
      \"name\": \"$THREAD_CONTACT_POINT\",
      \"type\": \"webhook\",
      \"settings\": {
        \"url\": \"$FUNCTION_URL\",
        \"httpMethod\": \"POST\",
        \"username\": \"$WEBHOOK_USER\",
        \"password\": \"$GRAFANA_PASSWORD\",
        \"authorization_scheme\": \"basic\"
      },
      \"disableResolveMessage\": false
    }" \
    "$GRAFANA_URL/api/v1/provisioning/contact-points")

  if echo "$CONTACT_RESPONSE" | jq -e '.name' > /dev/null 2>&1; then
    log_success "Thread analysis contact point created"
  else
    log_error "Thread analysis contact point creation failed:"
    echo "$CONTACT_RESPONSE" | jq .
  fi
else
  log_success "Thread analysis contact point already exists"
fi

# Create thread analysis alert rule
log_info "Creating thread analysis alert rule..."
THREAD_ALERT_PAYLOAD="{
  \"title\": \"$THREAD_ALERT_TITLE\",
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
  \"ruleGroup\": \"workshop-analysis-group\",
  \"annotations\": {
    \"summary\": \"High JVM Threads\",
    \"description\": \"High number of JVM threads detected. Triggering Lambda thread dump.\",
    \"webhookUrl\": \"$FUNCTION_URL\"
  },
  \"labels\": {
    \"severity\": \"critical\",
    \"alertname\": \"High JVM Threads\",
    \"analysis_type\": \"thread\"
  }
}"

if [[ -n "$FOLDER_UID" ]]; then
  THREAD_ALERT_PAYLOAD=$(echo "$THREAD_ALERT_PAYLOAD" | jq ". + {\"folderUID\": \"$FOLDER_UID\"}")
fi

ALERT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$THREAD_ALERT_PAYLOAD" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules")

log_success "Thread analysis alert rule created"

# Test Bedrock model access
log_info "Testing Bedrock model access..."
if aws bedrock-runtime invoke-model \
  --model-id "global.anthropic.claude-sonnet-4-20250514-v1:0" \
  --body "$(echo '{"anthropic_version": "bedrock-2023-05-31", "max_tokens": 10, "messages": [{"role": "user", "content": "Test"}]}' | base64)" \
  --region us-east-1 \
  /tmp/bedrock-test.json 2>/dev/null; then
  log_success "Bedrock model access verified"
  rm -f /tmp/bedrock-test.json
else
  log_warning "Bedrock model access test failed - Lambda may encounter issues"
fi


# =============================================================================
# SECTION 2: PROFILING ANALYSIS
# =============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 2: Profiling Analysis Setup"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create HTTP Metrics dashboard
log_info "Creating HTTP Metrics dashboard..."
cat > /tmp/http-dashboard.json <<EOF
{
  "title": "$HTTP_DASHBOARD_TITLE",
  "uid": "http-metrics-dashboard",
  "version": 1,
  "weekStart": "",
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "timepicker": {},
  "timezone": "browser",
  "links": [],
  "tags": ["http", "metrics", "workshop", "profiling"],
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "Prometheus"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisBorderShow": false,
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "reqps"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "Prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "code",
          "expr": "rate(http_server_requests_seconds_count{method=\"POST\"}[30s])",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "POST {{uri}} - {{status}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        }
      ],
      "title": "HTTP POST Request Rate",
      "type": "timeseries"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 39,
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-5m",
    "to": "now"
  }
}
EOF

DASHBOARD_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "{\"dashboard\": $(cat /tmp/http-dashboard.json), \"overwrite\": true, \"folderId\": $FOLDER_ID}" \
  "$GRAFANA_URL/api/dashboards/db")

HTTP_DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid')
rm /tmp/http-dashboard.json
log_success "HTTP Metrics dashboard created: $HTTP_DASHBOARD_UID"

# Create profiling analysis contact point
log_info "Creating profiling analysis contact point..."

EXISTING_PROFILING_CONTACT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points" | jq -r ".[] | select(.name == \"$PROFILING_CONTACT_POINT\") | .uid")

if [[ -n "$EXISTING_PROFILING_CONTACT" ]]; then
  log_info "Deleting existing profiling contact point..."
  echo "$EXISTING_PROFILING_CONTACT" | while read uid; do
    curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points/$uid"
  done
  sleep 2
fi

CONTACT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "{
    \"name\": \"$PROFILING_CONTACT_POINT\",
    \"type\": \"webhook\",
    \"settings\": {
      \"url\": \"http://ai-jvm-analyzer.monitoring.svc.cluster.local/webhook\",
      \"httpMethod\": \"POST\"
    },
    \"disableResolveMessage\": true
  }" \
  "$GRAFANA_URL/api/v1/provisioning/contact-points")

if echo "$CONTACT_RESPONSE" | jq -e '.name' > /dev/null 2>&1; then
  log_success "Profiling analysis contact point created"
else
  log_error "Profiling analysis contact point creation failed:"
  echo "$CONTACT_RESPONSE" | jq .
fi

# Create profiling analysis alert rule
log_info "Creating profiling analysis alert rule..."

# Check if alert rule already exists and delete it
EXISTING_PROFILING_ALERT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules" | jq -r ".[] | select(.title == \"$PROFILING_ALERT_TITLE\") | .uid // empty")

if [[ -n "$EXISTING_PROFILING_ALERT" ]]; then
  log_info "Deleting existing profiling alert rule..."
  curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules/$EXISTING_PROFILING_ALERT"
fi

PROFILING_ALERT_PAYLOAD="{
  \"title\": \"$PROFILING_ALERT_TITLE\",
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
  \"ruleGroup\": \"workshop-analysis-group\",
  \"annotations\": {
    \"summary\": \"High HTTP Rate\",
    \"description\": \"HTTP rate: {{ \$value }} req/s for pod {{ \$labels.pod }}\"
  },
  \"labels\": {
    \"severity\": \"warning\",
    \"alertname\": \"High HTTP Request Rate\",
    \"analysis_type\": \"profiling\"
  }
}"

if [[ -n "$FOLDER_UID" ]]; then
  PROFILING_ALERT_PAYLOAD=$(echo "$PROFILING_ALERT_PAYLOAD" | jq ". + {\"folderUID\": \"$FOLDER_UID\"}")
fi

ALERT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$PROFILING_ALERT_PAYLOAD" \
  "$GRAFANA_URL/api/v1/provisioning/alert-rules")

if echo "$ALERT_RESPONSE" | jq -e '.uid' > /dev/null 2>&1; then
  log_success "Profiling analysis alert rule created"
else
  log_error "Profiling analysis alert rule creation failed: $ALERT_RESPONSE"
fi


# =============================================================================
# SHARED NOTIFICATION POLICY
# =============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Configuring unified notification policy..."
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Configure notification policy with nested routes for both contact points
POLICY_PAYLOAD="{
  \"receiver\": \"grafana-default-email\",
  \"group_by\": [\"alertname\"],
  \"group_wait\": \"30s\",
  \"group_interval\": \"5m\",
  \"repeat_interval\": \"1h\",
  \"routes\": [
    {
      \"receiver\": \"$THREAD_CONTACT_POINT\",
      \"matchers\": [\"analysis_type=thread\"],
      \"group_wait\": \"30s\",
      \"group_interval\": \"5m\",
      \"repeat_interval\": \"1h\"
    },
    {
      \"receiver\": \"$PROFILING_CONTACT_POINT\",
      \"matchers\": [\"analysis_type=profiling\"],
      \"group_by\": [\"alertname\", \"pod\"],
      \"group_wait\": \"10s\",
      \"group_interval\": \"30s\",
      \"repeat_interval\": \"2m\"
    }
  ]
}"

POLICY_RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d "$POLICY_PAYLOAD" \
  "$GRAFANA_URL/api/v1/provisioning/policies")

if echo "$POLICY_RESPONSE" | grep -q "policies updated"; then
  log_success "Unified notification policy configured"
else
  log_error "Notification policy configuration failed:"
  echo "$POLICY_RESPONSE"
fi

# =============================================================================
# SUMMARY
# =============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Analysis setup complete!"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ""
log_info "Folder: $FOLDER_NAME"
log_info ""
log_info "Thread Analysis:"
log_info "   Dashboard: $THREAD_DASHBOARD_TITLE"
log_info "   Alert: $THREAD_ALERT_TITLE (threshold: $THREAD_THRESHOLD threads)"
log_info "   Webhook: $FUNCTION_URL"
log_info ""
log_info "Profiling Analysis:"
log_info "   Dashboard: $HTTP_DASHBOARD_TITLE"
log_info "   Alert: $PROFILING_ALERT_TITLE (threshold: $REQUESTS_THRESHOLD req/s)"
log_info "   Webhook: http://ai-jvm-analyzer.monitoring.svc.cluster.local/webhook"
log_info ""
log_info "Grafana: http://$GRAFANA_LB"
log_info "Username: $GRAFANA_USER"
log_info "Password: $GRAFANA_PASSWORD"

# Emit for bootstrap summary
echo "✅ Success: Analysis (Thread + Profiling dashboards)"
