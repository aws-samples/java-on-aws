#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

NAMESPACE="monitoring"
GRAFANA_USER="admin"
FOLDER_NAME="AI Agent Dashboards"
DASHBOARD_TITLE="Spring AI Metrics"
SECRET_NAME="unicornstore-ide-password-lambda"
application="unicorn-spring-ai-agent"

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

if [[ "$STATUS" != "ok" ]]; then
  log "❌ Grafana health check failed after 100 seconds"
  exit 1
fi

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

log "📊 Creating Spring AI dashboard..."
cat > /tmp/dashboard.json <<EOF
{
  "id": null,
  "title": "$DASHBOARD_TITLE",
  "tags": ["spring", "ai"],
  "timezone": "browser",
  "editable": true,
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 5,
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
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "sum by(gen_ai_operation_name, error, gen_ai_system, gen_ai_request_model) (rate(gen_ai_client_operation_seconds_count{application=\"$application\"}[\$__rate_interval]))",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "{{gen_ai_operation_name}} ({{gen_ai_system}}/{{gen_ai_request_model}}) - {{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        }
      ],
      "title": "Models Throughput",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "description": "Error counts/rate for the AI model requests",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
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
          "unit": "none"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 4,
        "x": 12,
        "y": 0
      },
      "id": 9,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "percentChangeColorMode": "standard",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showPercentChange": false,
        "textMode": "auto",
        "wideLayout": true
      },
      "pluginVersion": "11.1.4",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "gen_ai_client_operation_seconds_count{application=\"$application\", error!=\"none\"}",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": false,
          "instant": false,
          "legendFormat": "{{gen_ai_operation_name}}-{{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "db_vector_client_operation_seconds_count{application=\"$application\", error!=\"none\"}",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": false,
          "instant": false,
          "legendFormat": "{{db_system}}-{{error}}",
          "range": true,
          "refId": "B",
          "useBackend": false
        }
      ],
      "title": "Errors",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
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
          "unit": "Requests"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 4,
        "x": 16,
        "y": 0
      },
      "id": 10,
      "options": {
        "displayMode": "lcd",
        "maxVizHeight": 300,
        "minVizHeight": 16,
        "minVizWidth": 8,
        "namePlacement": "top",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showUnfilled": true,
        "sizing": "auto",
        "valueMode": "color"
      },
      "pluginVersion": "11.1.4",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "topk(10, sum by(gen_ai_operation_name, gen_ai_system, gen_ai_request_model) (increase(gen_ai_client_operation_seconds_count{application=\"$application\", error=\"none\"}[\$__rate_interval])))",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "{{gen_ai_operation_name}} ({{gen_ai_system}}/{{gen_ai_request_model}})",
          "range": true,
          "refId": "B",
          "useBackend": false
        }
      ],
      "title": "Top Models",
      "type": "bargauge"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "description": "Error counts/rate for the AI model requests",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            }
          },
          "mappings": []
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 4,
        "x": 20,
        "y": 0
      },
      "id": 8,
      "options": {
        "displayLabels": [
          "name",
          "value"
        ],
        "legend": {
          "displayMode": "table",
          "placement": "bottom",
          "showLegend": true,
          "values": [
            "percent"
          ]
        },
        "pieType": "donut",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "pluginVersion": "11.1.4",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "avg by(gen_ai_operation_name, error) (gen_ai_client_operation_seconds_count{application=\"$application\"})",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "{{gen_ai_operation_name}}-{{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        }
      ],
      "title": "Models Success vs Errors",
      "type": "piechart"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
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
          "unit": "Requests"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 4,
        "x": 16,
        "y": 4
      },
      "id": 13,
      "options": {
        "displayMode": "lcd",
        "maxVizHeight": 300,
        "minVizHeight": 16,
        "minVizWidth": 8,
        "namePlacement": "top",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showUnfilled": true,
        "sizing": "auto",
        "valueMode": "color"
      },
      "pluginVersion": "11.1.4",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "topk(10, sum by(db_system, db_operation_name) (increase(db_vector_client_operation_seconds_count{application=\"$application\", error=\"none\"}[\$__rate_interval])))",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "{{db_system}} ({{db_operation_name}})",
          "range": true,
          "refId": "B",
          "useBackend": false
        }
      ],
      "title": "Top Vector DBs",
      "type": "bargauge"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
            "barAlignment": -1,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "stepBefore",
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
          "unit": "s"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 0,
        "y": 8
      },
      "id": 7,
      "options": {
        "legend": {
          "calcs": [
            "lastNotNull"
          ],
          "displayMode": "table",
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
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "max by(error, gen_ai_operation_name, gen_ai_system, gen_ai_request_model) (gen_ai_client_operation_seconds_bucket{application=\"$application\"})",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Max - {{gen_ai_operation_name}} ({{gen_ai_system}}/{{gen_ai_request_model}}) - {{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "histogram_quantile(0.99, sum by(le, gen_ai_operation_name, gen_ai_request_model, error, gen_ai_system) (rate(gen_ai_client_operation_seconds_bucket{application=\"$application\"}[\$__rate_interval])))",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Tp99 - {{gen_ai_operation_name}} ({{gen_ai_system}}/{{gen_ai_request_model}}) - {{error}}",
          "range": true,
          "refId": "B",
          "useBackend": false
        }
      ],
      "title": "Models Latency",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
          "unit": "Tokens/sec"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 12,
        "y": 8
      },
      "id": 6,
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
      "pluginVersion": "11.1.4",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "sum by(gen_ai_operation_name, gen_ai_system) (rate(gen_ai_client_token_usage_total{application=\"$application\"}[\$__rate_interval]))",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "{{gen_ai_system}}-{{gen_ai_operation_name}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        }
      ],
      "title": "Token Usage Rate",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
        "h": 9,
        "w": 12,
        "x": 0,
        "y": 17
      },
      "id": 11,
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
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "sum by(db_system, db_operation_name, error) (rate(db_vector_client_operation_seconds_count{application=\"$application\"}[\$__rate_interval]))",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "{{db_system}}-{{db_operation_name}}-{{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        }
      ],
      "title": "Vector DB Throughput",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
            "barAlignment": -1,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "stepBefore",
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
          "unit": "s"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 12,
        "y": 17
      },
      "id": 12,
      "options": {
        "legend": {
          "calcs": [
            "lastNotNull"
          ],
          "displayMode": "table",
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
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "max by(db_operation_name, error, db_system) (db_vector_client_operation_seconds_max{application=\"$application\"})",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Max {{db_system}} ({{db_operation_name}}) - {{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "histogram_quantile(0.99, sum by(le, error, db_system, db_operation_name) (rate(db_vector_client_operation_seconds_bucket{application=\"$application\"}[\$__rate_interval])))",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Tp99 {{db_system}} ({{db_operation_name}}) - {{error}}",
          "range": true,
          "refId": "B",
          "useBackend": false
        }
      ],
      "title": "Vector DB Latency",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
        "h": 9,
        "w": 12,
        "x": 0,
        "y": 34
      },
      "id": 14,
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
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "sum by(error, spring_ai_chat_client_stream) (rate(spring_ai_chat_client_seconds_count{application=\"$application\"}[\$__rate_interval]))",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Stream: {{spring_ai_chat_client_stream}} - {{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        }
      ],
      "title": "Chat Client Throughput",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
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
            "barAlignment": -1,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "stepBefore",
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
          "unit": "s"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 12,
        "y": 34
      },
      "id": 15,
      "options": {
        "legend": {
          "calcs": [
            "lastNotNull"
          ],
          "displayMode": "table",
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
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "max by(error, spring_ai_chat_client_stream) (spring_ai_chat_client_seconds_max{application=\"$application\"})",
          "fullMetaSearch": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Max stream: {{spring_ai_chat_client_stream}} - {{error}}",
          "range": true,
          "refId": "A",
          "useBackend": false
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "disableTextWrap": false,
          "editorMode": "builder",
          "expr": "histogram_quantile(0.99, sum by(le, error, spring_ai_chat_client_stream) (rate(spring_ai_chat_client_seconds_bucket{application=\"$application\"}[\$__rate_interval])))",
          "fullMetaSearch": false,
          "hide": false,
          "includeNullMetadata": true,
          "instant": false,
          "legendFormat": "Tp99 stream: {{spring_ai_chat_client_stream}} - {{error}}",
          "range": true,
          "refId": "B",
          "useBackend": false
        }
      ],
      "title": "Chat Client Latency",
      "type": "timeseries"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 39,
  "tags": [],
  "templating": {
    "list": [
      {
        "current": {
          "selected": false,
          "text": "ai-observability-demo",
          "value": "ai-observability-demo"
        },
        "datasource": {
          "type": "prometheus",
          "uid": "prometheus"
        },
        "definition": "label_values(application)",
        "hide": 0,
        "includeAll": false,
        "multi": false,
        "name": "application",
        "options": [],
        "query": {
          "qryType": 1,
          "query": "label_values(application)",
          "refId": "PrometheusVariableQueryEditor-VariableQuery"
        },
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 0,
        "type": "query"
      }
    ]
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

log "✅ Spring AI dashboard created: $DASHBOARD_UID"

log "✅ Spring AI monitoring setup complete"
log "🌍 Grafana: $GRAFANA_URL"
log "📊 Dashboard shows Spring AI metrics from both EKS and ECS"
