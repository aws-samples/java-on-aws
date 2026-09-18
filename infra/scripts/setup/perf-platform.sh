#!/bin/bash

# =============================================================================
# Agentic Performance Platform Setup (immersion day: java-on-aws only)
# Provisions the perf-analyzer / perf-collector RBAC, the internal NLB that lets
# ECS Fargate collectors reach Pyroscope, the Latency Metrics dashboard, and the
# ServiceLatency alert wiring (contact point + notification policy).
#
# Runs after monitoring.sh, which now installs Pyroscope and the Grafana
# Pyroscope/CloudWatch datasources + pod identities (shared by both workshops).
# This script consumes those (CloudWatch datasource for the Latency dashboard,
# Pyroscope Service for the NLB) and does not install or configure them itself.
#
# The EKS-only CON405 template does NOT run this script — it drives optimization
# from the perf-optimizer MCP agent, which brings its own SA, dashboard, and
# read-only RBAC (see deploy/java-on-amazon-eks/perf-optimizer.sh).
# =============================================================================

set -eo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

log_info "Starting agentic performance platform setup..."

# Source environment variables
source /etc/profile.d/workshop.sh

PREFIX="${PREFIX:-workshop}"
NAMESPACE="monitoring"
GRAFANA_USER="admin"
CONTACT_POINT_NAME="perf-analyzer-webhook"
ANALYZER_WEBHOOK_URL="http://perf-analyzer.${NAMESPACE}.svc.cluster.local:8080/api/v1/grafana-webhook"

# Working files (cleaned up on exit)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# =============================================================================
# Prerequisites
# =============================================================================

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || {
    log_error "Namespace ${NAMESPACE} not found. Run monitoring.sh first."
    exit 1
}

# =============================================================================
# RBAC for perf-analyzer and perf-collector
# =============================================================================

log_info "Applying RBAC for perf-analyzer..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perf-analyzer
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-analyzer
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-analyzer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: perf-analyzer
subjects:
  - kind: ServiceAccount
    name: perf-analyzer
    namespace: ${NAMESPACE}
EOF

log_info "Applying RBAC for perf-collector..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perf-collector
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-collector
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-collector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: perf-collector
subjects:
  - kind: ServiceAccount
    name: perf-collector
    namespace: ${NAMESPACE}
EOF

log_success "RBAC applied"

# =============================================================================
# Internal NLB (fronts Pyroscope for ECS Fargate reachability)
# =============================================================================

log_info "Provisioning internal NLB for ECS Fargate reachability..."
# Single NLB fronts Pyroscope. ECS Fargate collectors use it to reach Pyroscope
# from outside the cluster. The analyzer is never called from outside the
# cluster — developers invoke it via `kubectl run` + cluster DNS, and Grafana's
# webhook uses cluster DNS too, so it needs no NLB.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pyroscope-nlb
  namespace: ${NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
    service.beta.kubernetes.io/aws-load-balancer-name: perf-platform-internal
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: pyroscope
  ports:
    - name: pyroscope
      port: 4040
      targetPort: 4040
      protocol: TCP
EOF

log_info "Waiting for pyroscope-nlb to provision..."
NLB_DNS=""
for i in {1..60}; do
    NLB_DNS=$(kubectl get svc pyroscope-nlb -n "${NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "${NLB_DNS}" ]]; then
        break
    fi
    sleep 10
done

if [[ -z "${NLB_DNS}" ]]; then
    log_error "NLB DNS was not assigned within 10 minutes"
    exit 1
fi

# NLB DNS is owned by the Service object. Consumers (the workshop content's ECS
# Fargate sidecar setup, anything else that needs Pyroscope from outside the
# cluster) look it up at the time of need:
#   kubectl get svc pyroscope-nlb -n monitoring \
#     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
log_success "Internal NLB ready: ${NLB_DNS}"

# =============================================================================
# Grafana connection (Grafana + folder + CloudWatch datasource already provided
# by monitoring.sh; this script only adds the dashboard, contact point, policy).
# =============================================================================

log_info "Configuring Grafana..."

SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "${PREFIX}-ide-password" \
    --query 'SecretString' --output text --no-cli-pager)
GRAFANA_PASSWORD=$(echo "${SECRET_VALUE}" | jq -r '.password')

GRAFANA_LB=$(kubectl get svc grafana -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [[ -z "${GRAFANA_LB}" ]]; then
    log_error "Grafana LoadBalancer not found. Run monitoring.sh first."
    exit 1
fi
GRAFANA_URL="http://${GRAFANA_LB}"

log_info "Waiting for Grafana API to be ready..."
for i in {1..40}; do
    STATUS=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/health" \
        | jq -r .database 2>/dev/null || true)
    if [[ "${STATUS}" == "ok" ]]; then
        log_info "Grafana API ready"
        break
    fi
    [[ $i -eq 40 ]] && { log_error "Grafana API not ready after 200s"; exit 1; }
    sleep 5
done

CLUSTER_NAME="${PREFIX}-eks"

# -----------------------------------------------------------------------------
# Grafana CloudWatch — Pod Identity for read-only metrics access + datasource.
# Module-specific (Latency Metrics dashboard + ServiceLatency alert read ALB
# metrics from CloudWatch). Not part of the shared monitoring stack.
# -----------------------------------------------------------------------------
log_info "Binding Grafana ServiceAccount to grafana-eks-pod-role..."
if ! aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
        --query "associations[?serviceAccount=='grafana' && namespace=='${NAMESPACE}']" \
        --output text --no-cli-pager | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name "${CLUSTER_NAME}" \
        --namespace "${NAMESPACE}" \
        --service-account grafana \
        --role-arn "$(aws iam get-role --role-name grafana-eks-pod-role \
            --query 'Role.Arn' --output text --no-cli-pager)" \
        --no-cli-pager
    log_success "Grafana CloudWatch pod identity association created"
else
    log_info "Grafana CloudWatch pod identity association already exists"
fi

# EKS Pod Identity associations are eventually consistent. Recreate Grafana until
# the current Running/Ready pod has the injected credential endpoint. This also
# repairs an existing pod that predates its association.
GRAFANA_POD=""
for i in {1..6}; do
    if (( i > 1 )); then
        log_info "Pod Identity credentials not injected yet; waiting before retry ${i}/6..."
        sleep 10
    fi
    log_info "Restarting Grafana to pick up Pod Identity credentials (${i}/6)..."
    kubectl rollout restart deployment/grafana -n "${NAMESPACE}"
    kubectl rollout status deployment/grafana -n "${NAMESPACE}" --timeout=180s
    GRAFANA_POD=$(kubectl get pods -n "${NAMESPACE}" \
        -l app.kubernetes.io/name=grafana -o json \
        | jq -r '[.items[]
            | select(.metadata.deletionTimestamp == null and .status.phase == "Running")
            | select([.status.containerStatuses[]?.ready] | all)
            | select([.spec.containers[].env[]?.name]
                | index("AWS_CONTAINER_CREDENTIALS_FULL_URI"))
            | .metadata.name] | first // empty')
    [[ -n "${GRAFANA_POD}" ]] && break
done
if [[ -z "${GRAFANA_POD}" ]]; then
    log_error "Grafana did not receive EKS Pod Identity credentials after 6 restarts"
    exit 1
fi
log_success "Grafana pod ${GRAFANA_POD} received EKS Pod Identity credentials"

log_info "Waiting for Grafana API after pod restart..."
for i in {1..40}; do
    STATUS=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/health" \
        | jq -r .database 2>/dev/null || true)
    [[ "${STATUS}" == "ok" ]] && break
    [[ $i -eq 40 ]] && { log_error "Grafana API not ready after 200s"; exit 1; }
    sleep 5
done

log_info "Provisioning Grafana CloudWatch datasource..."
cat > "${WORK}/cloudwatch-datasource.yaml" <<EOF
apiVersion: 1
datasources:
  - uid: cloudwatch
    name: CloudWatch
    type: cloudwatch
    access: proxy
    isDefault: false
    editable: true
    jsonData:
      authType: default
      defaultRegion: ${AWS_REGION}
EOF
kubectl create configmap perf-platform-cloudwatch-datasource \
    --from-file="${WORK}/cloudwatch-datasource.yaml" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap perf-platform-cloudwatch-datasource \
    -n "${NAMESPACE}" grafana_datasource=1 --overwrite

log_info "Verifying Grafana CloudWatch datasource credentials..."
for i in {1..12}; do
    CLOUDWATCH_RESPONSE=$(curl -sS -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        -w $'\n%{http_code}' \
        "${GRAFANA_URL}/api/datasources/uid/cloudwatch/health" 2>&1 || true)
    CLOUDWATCH_HTTP_STATUS="${CLOUDWATCH_RESPONSE##*$'\n'}"
    CLOUDWATCH_HEALTH="${CLOUDWATCH_RESPONSE%$'\n'*}"
    if [[ "${CLOUDWATCH_HTTP_STATUS}" == "200" ]] \
            && jq -e '
                .status == "OK"
                or ((.message // "")
                    | contains("Successfully queried the CloudWatch metrics API."))
            ' <<<"${CLOUDWATCH_HEALTH}" >/dev/null 2>&1; then
        break
    fi
    [[ $i -eq 12 ]] && {
        CLOUDWATCH_MESSAGE=$(jq -r '.message // empty' <<<"${CLOUDWATCH_HEALTH}" 2>/dev/null || true)
        [[ -z "${CLOUDWATCH_MESSAGE}" ]] && CLOUDWATCH_MESSAGE="${CLOUDWATCH_HEALTH:-empty response}"
        log_error "Grafana CloudWatch datasource is unhealthy (HTTP ${CLOUDWATCH_HTTP_STATUS}): ${CLOUDWATCH_MESSAGE}"
        exit 1
    }
    sleep 5
done
log_success "Grafana CloudWatch metrics access verified"

# =============================================================================
# Latency Metrics dashboard — two rows, five panels:
#   Row 1 — Latency: ALB p99 TargetResponseTime time series + p99 stat
#   Row 2 — Throughput and errors: RequestCount + 5xx counts (target + ELB)
# Lives in the "Workshop Dashboards" folder alongside other workshop dashboards.
# Picks up any ALB(s) the participant deploys later — no pre-baked LB names.
# Reads via the CloudWatch datasource provisioned above.
# =============================================================================

log_info "Provisioning Latency Metrics dashboard..."
WORKSHOP_FOLDER_UID=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/folders" \
    | jq -r '.[] | select(.title == "Workshop Dashboards") | .uid' 2>/dev/null || echo "")
if [[ -z "${WORKSHOP_FOLDER_UID}" ]]; then
    log_error "Workshop Dashboards folder not found in Grafana. Run monitoring.sh first."
    exit 1
fi
cat > "${WORK}/latency-metrics-dashboard.json" <<'DASHBOARD_EOF'
{
  "title": "Latency Metrics",
  "uid": "perf-platform-latency",
  "tags": ["http", "latency", "metrics", "workshop"],
  "timezone": "browser",
  "schemaVersion": 39,
  "refresh": "30s",
  "time": { "from": "now-15m", "to": "now" },
  "templating": { "list": [] },
  "panels": [
    {
      "type": "row",
      "id": 100,
      "title": "Latency",
      "gridPos": { "x": 0, "y": 0, "w": 24, "h": 1 },
      "collapsed": false
    },
    {
      "type": "timeseries",
      "id": 1,
      "title": "ALB p99 TargetResponseTime",
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "gridPos": { "x": 0, "y": 1, "w": 18, "h": 9 },
      "fieldConfig": {
        "defaults": {
          "unit": "s",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "red", "value": 1 }
            ]
          },
          "custom": { "thresholdsStyle": { "mode": "line+area" } }
        }
      },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 1,
          "region": "default",
          "namespace": "AWS/ApplicationELB",
          "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"TargetResponseTime\"', 'p99', 60)",
          "statistic": "p99",
          "period": "60",
          "dimensions": {},
          "matchExact": true
        }
      ]
    },
    {
      "type": "stat",
      "id": 2,
      "title": "Current p99",
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "gridPos": { "x": 18, "y": 1, "w": 6, "h": 9 },
      "fieldConfig": {
        "defaults": {
          "unit": "s",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "red", "value": 1 }
            ]
          },
          "color": { "mode": "thresholds" }
        }
      },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
        "colorMode": "background",
        "graphMode": "area"
      },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 1,
          "region": "default",
          "namespace": "AWS/ApplicationELB",
          "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"TargetResponseTime\"', 'p99', 60)",
          "statistic": "p99",
          "period": "60",
          "dimensions": {},
          "matchExact": true
        }
      ]
    },
    {
      "type": "row",
      "id": 200,
      "title": "Throughput and errors",
      "gridPos": { "x": 0, "y": 10, "w": 24, "h": 1 },
      "collapsed": false
    },
    {
      "type": "timeseries",
      "id": 3,
      "title": "Request rate",
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "gridPos": { "x": 0, "y": 11, "w": 12, "h": 9 },
      "fieldConfig": { "defaults": { "unit": "reqps" } },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 1,
          "region": "default",
          "namespace": "AWS/ApplicationELB",
          "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"RequestCount\"', 'Sum', 60)",
          "statistic": "Sum",
          "period": "60",
          "dimensions": {},
          "matchExact": true
        }
      ]
    },
    {
      "type": "timeseries",
      "id": 4,
      "title": "5xx errors per minute",
      "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
      "gridPos": { "x": 12, "y": 11, "w": 12, "h": 9 },
      "fieldConfig": {
        "defaults": {
          "unit": "short",
          "color": { "mode": "thresholds" },
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "red", "value": 1 }
            ]
          }
        }
      },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 1,
          "region": "default",
          "namespace": "AWS/ApplicationELB",
          "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"HTTPCode_Target_5XX_Count\"', 'Sum', 60)",
          "statistic": "Sum",
          "period": "60",
          "dimensions": {},
          "matchExact": true
        },
        {
          "refId": "B",
          "datasource": { "type": "cloudwatch", "uid": "cloudwatch" },
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 1,
          "region": "default",
          "namespace": "AWS/ApplicationELB",
          "expression": "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"HTTPCode_ELB_5XX_Count\"', 'Sum', 60)",
          "statistic": "Sum",
          "period": "60",
          "dimensions": {},
          "matchExact": true
        }
      ]
    }
  ]
}
DASHBOARD_EOF
jq -c "{dashboard: ., folderUid: \"${WORKSHOP_FOLDER_UID}\", overwrite: true}" \
    "${WORK}/latency-metrics-dashboard.json" > "${WORK}/latency-dashboard-payload.json"
DASHBOARD_RESPONSE=$(curl -s -X POST -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -H "Content-Type: application/json" \
    --data "@${WORK}/latency-dashboard-payload.json" \
    "${GRAFANA_URL}/api/dashboards/db")
if echo "${DASHBOARD_RESPONSE}" | jq -e '.uid' >/dev/null 2>&1; then
    log_success "Latency Metrics dashboard provisioned"
else
    log_error "Dashboard creation failed: ${DASHBOARD_RESPONSE}"
    exit 1
fi

# =============================================================================
# ServiceLatency contact point + notification policy
# Alert rule creation is deferred to the workshop module (Ch 4): it depends on
# the participant-deployed ALB ARN(s), which only exist after unicorn-store-spring
# is rolled out. This script provisions the infrastructure the rule references.
# =============================================================================

# Contact point.
EXISTING=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/contact-points" \
    | jq -r ".[] | select(.name == \"${CONTACT_POINT_NAME}\") | .uid" 2>/dev/null || true)
if [[ -n "${EXISTING}" ]]; then
    curl -s -X DELETE -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/contact-points/${EXISTING}" >/dev/null
fi

CONTACT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -d "{
      \"name\": \"${CONTACT_POINT_NAME}\",
      \"type\": \"webhook\",
      \"settings\": {
        \"url\": \"${ANALYZER_WEBHOOK_URL}\",
        \"httpMethod\": \"POST\"
      },
      \"disableResolveMessage\": true
    }" \
    "${GRAFANA_URL}/api/v1/provisioning/contact-points")

if echo "${CONTACT_RESPONSE}" | jq -e '.name' >/dev/null 2>&1; then
    log_success "Contact point ${CONTACT_POINT_NAME} created"
else
    log_error "Contact point creation failed: ${CONTACT_RESPONSE}"
    exit 1
fi

log_info "Removing any stale ServiceLatency alert rule from a previous run..."
EXISTING_ALERT=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    | jq -r '.[] | select(.title == "ServiceLatency") | .uid' 2>/dev/null || true)
if [[ -n "${EXISTING_ALERT}" ]]; then
    curl -s -X DELETE -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${EXISTING_ALERT}" >/dev/null
    log_info "  Removed previous ServiceLatency rule"
fi

# Notification policy — upsert this module's route only, keyed by receiver name.
# analysis.sh owns its own routes (thread-dump-lambda-webhook,
# ai-jvm-analyzer-webhook); this script owns ${CONTACT_POINT_NAME}. Whoever runs
# last does not clobber the other modules' routes.
log_info "Upserting notification policy route for ${CONTACT_POINT_NAME}..."
EXISTING_POLICY=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/policies")

NEW_ROUTE='{
  "receiver": "'"${CONTACT_POINT_NAME}"'",
  "matchers": ["analysis_type=perf-platform"],
  "group_by": ["alertname", "service_name"],
  "group_wait": "10s",
  "group_interval": "30s",
  "repeat_interval": "2m"
}'

POLICY_BODY=$(echo "${EXISTING_POLICY}" | jq \
    --argjson new "${NEW_ROUTE}" \
    --arg cp "${CONTACT_POINT_NAME}" '
      .receiver        = (.receiver        // "grafana-default-email")
    | .group_by        = (.group_by        // ["alertname"])
    | .group_wait      = (.group_wait      // "30s")
    | .group_interval  = (.group_interval  // "5m")
    | .repeat_interval = (.repeat_interval // "1h")
    | .routes          = ((.routes // []) | map(select(.receiver != $cp))) + [$new]
')

POLICY_RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -d "${POLICY_BODY}" \
    "${GRAFANA_URL}/api/v1/provisioning/policies")

if echo "${POLICY_RESPONSE}" | grep -q "policies updated"; then
    log_success "Notification policy route for ${CONTACT_POINT_NAME} upserted"
else
    log_warning "Notification policy update response: ${POLICY_RESPONSE}"
fi

# =============================================================================
# Summary
# =============================================================================

log_info ""
log_info "Agentic performance platform ready."
log_info "  Internal NLB DNS:   ${NLB_DNS}  (kubectl get svc pyroscope-nlb -n monitoring)"
log_info "  Analyzer webhook:   ${ANALYZER_WEBHOOK_URL}"
log_info "  Grafana datasource: CloudWatch (read-only via grafana-eks-pod-role)"
log_info "  Grafana dashboard:  Workshop Dashboards / Latency Metrics"
log_info "  Grafana contact pt: ${CONTACT_POINT_NAME}"
log_info ""
log_info "Next: participants deploy perf-analyzer (module S1) and perf-collector (module S2),"
log_info "      then create the ServiceLatency alert rule pointed at their ALB (module S4)."

echo "✅ Success: Perf Platform (NLB + perf-analyzer/collector RBAC + Latency dashboard + alert wiring)"
