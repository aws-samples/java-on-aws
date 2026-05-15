#!/bin/bash

# =============================================================================
# Agentic Performance Platform Setup
# Installs Pyroscope (with native recording rules), Kyverno JFR policy,
# Grafana alert wiring, internal NLB, and RBAC used by the perf-analyzer module.
#
# Runs in workshop bootstrap, after monitoring.sh (requires Prometheus+Grafana).
# Does not modify existing scripts or modules.
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

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

CLUSTER_NAME="${PREFIX}-eks"
WORKSHOP_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name \
    --query 'Parameter.Value' --output text --no-cli-pager)
if [[ -z "${WORKSHOP_BUCKET}" || "${WORKSHOP_BUCKET}" == "None" ]]; then
    log_error "SSM parameter workshop-bucket-name is not set. Aborting."
    exit 1
fi

# =============================================================================
# Pyroscope Pod Identity — bind the Pyroscope ServiceAccount to the CDK-managed
# pyroscope-eks-pod-role BEFORE installing Pyroscope, so the very first pod
# boot has S3 creds available.
# =============================================================================

log_info "Binding Pyroscope ServiceAccount to pyroscope-eks-pod-role..."
# Create the ServiceAccount up front so the pod identity webhook has something
# to bind to. Helm will adopt it on install because names/namespaces match.
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pyroscope
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: pyroscope
EOF

if ! aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
        --query "associations[?serviceAccount=='pyroscope' && namespace=='${NAMESPACE}']" \
        --output text --no-cli-pager | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name "${CLUSTER_NAME}" \
        --namespace "${NAMESPACE}" \
        --service-account pyroscope \
        --role-arn "$(aws iam get-role --role-name pyroscope-eks-pod-role \
            --query 'Role.Arn' --output text --no-cli-pager)" \
        --no-cli-pager
    log_success "Pyroscope pod identity association created"
    sleep 10
else
    log_info "Pyroscope pod identity association already exists"
fi

# =============================================================================
# Pyroscope (S3-backed single-binary, blocks under s3://<bucket>/pyroscope/)
# =============================================================================

log_info "Installing Pyroscope..."
cat > "${WORK}/pyroscope-values.yaml" <<EOF
pyroscope:
  service:
    type: ClusterIP
    port: 4040
    # Expose /metrics on the same port; prometheus.io annotations below.
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "4040"
      prometheus.io/path: /metrics
  # PVC not needed — Pyroscope v2 writes blocks directly to S3.
  persistence:
    enabled: false
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 2Gi
  # structuredConfig uses Pyroscope 2.x top-level keys only.
  # 1.x fields \`auth_enabled\` and \`recording_rules\` were removed in 2.x
  # and cause CrashLoopBackOff if included.
  structuredConfig:
    storage:
      backend: s3
      # Isolate Pyroscope blocks inside the shared workshop bucket.
      prefix: pyroscope
      s3:
        bucket_name: ${WORKSHOP_BUCKET}
        region: ${AWS_REGION}
        endpoint: s3.${AWS_REGION}.amazonaws.com
        # AWS SDK default credential chain — picks up EKS Pod Identity creds.
        native_aws_auth_enabled: true
    limits:
      retention_period: 168h
EOF

helm upgrade --install pyroscope grafana/pyroscope \
    --namespace "${NAMESPACE}" \
    --values "${WORK}/pyroscope-values.yaml" \
    --wait --timeout 10m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=pyroscope \
    -n "${NAMESPACE}" --timeout=600s

log_success "Pyroscope installed"

# =============================================================================
# RBAC for perf-analyzer and perf-collector
# =============================================================================

log_info "Applying RBAC for perf-analyzer and perf-collector..."

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
---
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
# Internal NLB (two annotated LoadBalancer Services sharing one NLB)
# =============================================================================

log_info "Provisioning internal NLB for ECS Fargate reachability..."
# Single NLB fronts Pyroscope. ECS Fargate collectors use it to reach
# Pyroscope from outside the cluster. The analyzer is never called from
# outside the cluster — developers invoke it via `kubectl run` + cluster
# DNS, Grafana's webhook uses cluster DNS too, so it needs no NLB.
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

# NLB DNS is owned by the Service object. Consumers (the workshop content's
# ECS Fargate sidecar setup, anything else that needs Pyroscope from outside
# the cluster) look it up at the time of need:
#   kubectl get svc pyroscope-nlb -n monitoring \
#     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
log_success "Internal NLB ready: ${NLB_DNS}"

# =============================================================================
# Grafana Pyroscope datasource + Profiles Drilldown plugin
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

# Install Profiles Drilldown plugin (idempotent).
log_info "Installing Grafana Profiles Drilldown plugin..."
helm upgrade --install grafana grafana/grafana \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --set "plugins={grafana-pyroscope-app}" \
    --wait --timeout 5m
log_success "Profiles Drilldown plugin installed"

# Wait for Grafana API to be ready after the helm upgrade restarts the pod.
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

# Pyroscope datasource.
log_info "Provisioning Grafana Pyroscope datasource..."
cat > "${WORK}/pyroscope-datasource.yaml" <<EOF
apiVersion: 1
datasources:
  - uid: pyroscope
    name: Pyroscope
    type: grafana-pyroscope-datasource
    access: proxy
    url: http://pyroscope.${NAMESPACE}.svc.cluster.local:4040
    isDefault: false
    editable: true
EOF
kubectl create configmap perf-platform-pyroscope-datasource \
    --from-file="${WORK}/pyroscope-datasource.yaml" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap perf-platform-pyroscope-datasource \
    -n "${NAMESPACE}" grafana_datasource=1 --overwrite
log_success "Grafana Pyroscope datasource provisioned"

# =============================================================================
# Grafana CloudWatch — pod identity for read-only metrics access, plus a
# CloudWatch datasource and a "Latency Metrics" dashboard. Used by the Ch 4
# alert rule (created in the workshop module) to fire on ALB p99
# TargetResponseTime > 1s.
# =============================================================================

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
    # Restart Grafana so the credentials get attached to a fresh pod.
    kubectl rollout restart deployment/grafana -n "${NAMESPACE}"
    kubectl rollout status deployment/grafana -n "${NAMESPACE}" --timeout=180s
    # Re-wait for the API since the pod restarted.
    log_info "Waiting for Grafana API after pod restart..."
    for i in {1..40}; do
        STATUS=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/health" \
            | jq -r .database 2>/dev/null || true)
        if [[ "${STATUS}" == "ok" ]]; then break; fi
        [[ $i -eq 40 ]] && { log_error "Grafana API not ready after 200s"; exit 1; }
        sleep 5
    done
else
    log_info "Grafana CloudWatch pod identity association already exists"
fi

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
log_success "Grafana CloudWatch datasource provisioned"

# =============================================================================
# Latency Metrics dashboard — two rows, five panels:
#   Row 1 — Latency: ALB p99 TargetResponseTime time series + p99 stat
#   Row 2 — Throughput and errors: RequestCount + 5xx counts (target + ELB)
# Lives in the "Workshop Dashboards" folder alongside other workshop dashboards.
# Picks up any ALB(s) the participant deploys later — no pre-baked LB names.
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

# Alert rule creation is deferred to the workshop module (Ch 4). It depends on
# the participant-deployed ALB ARN(s), which only exist after the unicorn-store-spring
# workload is rolled out. perf-platform.sh provisions the *infrastructure* the
# alert rule will reference (CloudWatch datasource, IAM role, contact point,
# notification policy, dashboard); the rule itself is created in the chapter
# with the discovered ALB plugged into the dimension.
log_info "Removing any stale ServiceLatency alert rule from a previous run..."
EXISTING_ALERT=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    | jq -r '.[] | select(.title == "ServiceLatency") | .uid' 2>/dev/null || true)
if [[ -n "${EXISTING_ALERT}" ]]; then
    curl -s -X DELETE -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${EXISTING_ALERT}" >/dev/null
    log_info "  Removed previous ServiceLatency rule"
fi

# Notification policy — upsert this module's route only, keyed by receiver
# name. analysis.sh owns its own routes (thread-dump-lambda-webhook,
# ai-jvm-analyzer-webhook); this script owns ${CONTACT_POINT_NAME}. Whoever
# runs last does not clobber the other modules' routes.
log_info "Upserting notification policy route for ${CONTACT_POINT_NAME}..."
EXISTING_POLICY=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/policies")

NEW_ROUTE='{
  "receiver": "'"${CONTACT_POINT_NAME}"'",
  "matchers": ["analysis_type=profiling"],
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
log_info "  Pyroscope:          http://pyroscope.${NAMESPACE}.svc.cluster.local:4040  (S3-backed, prefix s3://${WORKSHOP_BUCKET}/pyroscope/)"
log_info "  Internal NLB DNS:   ${NLB_DNS}  (kubectl get svc pyroscope-nlb -n monitoring)"
log_info "  Analyzer webhook:   ${ANALYZER_WEBHOOK_URL}"
log_info "  Grafana datasource: CloudWatch (read-only via grafana-eks-pod-role)"
log_info "  Grafana dashboard:  Workshop Dashboards / Latency Metrics"
log_info "  Grafana contact pt: ${CONTACT_POINT_NAME}"
log_info "  Profiles Drilldown: installed in Grafana"
log_info ""
log_info "Next: participants deploy perf-analyzer (module S1) and perf-collector (module S2),"
log_info "      then create the ServiceLatency alert rule pointed at their ALB (module S4)."

echo "✅ Success: Perf Platform (Pyroscope S3 + NLB + CloudWatch + Grafana wiring)"
