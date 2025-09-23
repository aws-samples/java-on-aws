#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

NAMESPACE="monitoring"
GRAFANA_USER="admin"
SECRET_NAME="unicornstore-ide-password-lambda"
FOLDER_NAME="JVM Metrics"
DASHBOARD_TITLE="HTTP Metrics"

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

log "📊 Creating HTTP metrics dashboard..."
cat > /tmp/dashboard.json <<EOF
{
  "title": "$DASHBOARD_TITLE",
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
  "tags": ["http", "metrics"],
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
  -d "{\"dashboard\": $(cat /tmp/dashboard.json), \"overwrite\": true, \"folderId\": $FOLDER_ID}" \
  "$GRAFANA_URL/api/dashboards/db")

DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid')
rm /tmp/dashboard.json

log "✅ HTTP metrics dashboard created: $DASHBOARD_UID"

log "📊 Dashboard shows HTTP requests metrics"
