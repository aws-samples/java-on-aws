#!/bin/bash
# =============================================================================
# perf-sensor — deterministic performance sensors for a Java workload on EKS,
# exposed over MCP (streamable-http) + REST. No Bedrock, no Spring AI chat, no
# AWS SDK, no Pod Identity (the sensor makes no AWS calls).
#
# Builds and pushes the image (jib -> ECR), then applies:
#   - ServiceAccount + read-only ClusterRole (get/list/watch; pods/log for startup)
#   - Deployment + Service in the monitoring namespace
#   - a NetworkPolicy in the app namespace allowing ingress to the profiler
#     sidecar /dump port (9100) ONLY from monitoring pods labelled app=perf-sensor
#
# Runs on the IDE instance as ec2-user with the IDE role. CON405 (EKS-only).
# Not wired into templates/java-on-amazon-eks.sh until the PoC verdict.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Optional workshop context (present on the IDE); safe to skip elsewhere.
[ -f "${SCRIPT_DIR}/../../lib/common.sh" ] && source "${SCRIPT_DIR}/../../lib/common.sh"
LOG="${WORKSHOP_LOG_DIR}/perf-sensor-build.log"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh

# Minimal log helpers if common.sh is not present.
command -v log_info >/dev/null 2>&1 || {
  log_info()    { echo "ℹ️  $*"; }
  log_success() { echo "✅ $*"; }
  log_warning() { echo "⚠️  $*"; }
  log_error()   { echo "❌ $*" >&2; }
}

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/perf-sensor"
K8S_DIR="${APP_DIR}/k8s"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="${ECR_BASE}/perf-sensor"
NS="monitoring"
APP_NS="${APP_NS:-unicorn-store-spring}"   # namespace of the workload being measured

# -----------------------------------------------------------------------------
# 1. Build + push the image. Ensure the ECR repo exists first — the account's
#    create-on-push template does not always cover a new perf-* repo, so create
#    it idempotently (same pattern as test/perf-scenario.sh's ensure_repo).
# -----------------------------------------------------------------------------
log_info "Ensuring ECR repository perf-sensor exists..."
aws ecr describe-repositories --repository-names perf-sensor --region "${REGION}" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name perf-sensor --region "${REGION}" >/dev/null \
  || { log_error "could not create ECR repo perf-sensor"; exit 1; }

log_info "Building and pushing perf-sensor image..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_BASE}"
( cd "${APP_DIR}" && mvn -q clean compile jib:build -Dimage="${REPO}:latest" ) >>"$LOG" 2>&1 \
  || { log_error "perf-sensor build failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
log_success "perf-sensor image pushed: ${REPO}:latest"

# -----------------------------------------------------------------------------
# 2. ServiceAccount + read-only ClusterRole (no write verbs, no Pod Identity).
# -----------------------------------------------------------------------------
log_info "Applying perf-sensor SA + read-only ClusterRole..."
sed "s|__NS__|${NS}|g" "${K8S_DIR}/rbac.yaml" | kubectl apply -f -
log_success "RBAC applied (get/list/watch only)"

# -----------------------------------------------------------------------------
# 3. Deployment + Service in the monitoring namespace.
# -----------------------------------------------------------------------------
log_info "Deploying perf-sensor to ${NS}..."
sed -e "s|__IMAGE__|${REPO}:latest|g" -e "s|__NS__|${NS}|g" \
  "${K8S_DIR}/deployment.yaml" | kubectl apply -f -

# -----------------------------------------------------------------------------
# 4. NetworkPolicy in the app namespace: ingress to sidecar /dump (9100) only
#    from monitoring pods labelled app=perf-sensor.
# -----------------------------------------------------------------------------
log_info "Applying /dump NetworkPolicy in ${APP_NS}..."
sed -e "s|__APP_NS__|${APP_NS}|g" -e "s|__MONITORING_NS__|${NS}|g" \
  "${K8S_DIR}/networkpolicy.yaml" | kubectl apply -f - \
  || log_warning "NetworkPolicy apply failed (namespace ${APP_NS} present? CNI enforces policy?)"

# Force a fresh pull of the just-built :latest.
kubectl -n "${NS}" rollout restart deploy/perf-sensor >/dev/null 2>&1 || true
kubectl -n "${NS}" rollout status deploy/perf-sensor --timeout=200s || {
  log_error "rollout not ready; recent logs:"; kubectl -n "${NS}" logs -l app=perf-sensor --tail=60; exit 1; }

# -----------------------------------------------------------------------------
# 5. Grafana dashboard — the sensor's numbers, plus the two panels the old
#    Optimization dashboard lacked: p99 request latency (Q5 blocking-call fix) and
#    fleet memory reserved-vs-used (the right-sizing cost story at N replicas).
#    Shipped as a ConfigMap the Grafana sidecar imports (label grafana_dashboard=1).
# -----------------------------------------------------------------------------
log_info "Provisioning 'Java on EKS — Sensor' dashboard..."
DASH=$(mktemp)
cat > "${DASH}" <<DASH_EOF
{
  "title": "Java on EKS — Sensor",
  "uid": "perf-sensor-eks",
  "tags": ["optimization","java","workshop","perf-sensor"],
  "timezone": "browser", "schemaVersion": 39, "refresh": "5s",
  "time": { "from": "now-5m", "to": "now" }, "templating": { "list": [] },
  "panels": [
    { "type": "row", "id": 100, "title": "At a glance", "gridPos": {"x":0,"y":0,"w":24,"h":1} },
    { "type": "stat", "id": 1, "title": "Startup (ready time)", "gridPos": {"x":0,"y":1,"w":5,"h":4},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"s"}},
      "targets": [{"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
        "expr":"max(perf_sensor_startup_seconds{service=\"${APP_NS}\"})"}] },
    { "type": "stat", "id": 2, "title": "Request latency (max)", "gridPos": {"x":5,"y":1,"w":5,"h":4},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"s"}},
      "targets": [{"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
        "expr":"max(http_server_requests_seconds_max{application=\"${APP_NS}\"})"}] },
    { "type": "stat", "id": 3, "title": "Memory reserved (fleet)", "gridPos": {"x":10,"y":1,"w":5,"h":4},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"bytes"}},
      "targets": [{"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
        "expr":"sum(kube_pod_container_resource_limits{namespace=\"${APP_NS}\",container=\"${APP_NS}\",resource=\"memory\"})"}] },
    { "type": "stat", "id": 4, "title": "Memory used (fleet)", "gridPos": {"x":15,"y":1,"w":5,"h":4},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"bytes"}},
      "targets": [{"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
        "expr":"sum(container_memory_working_set_bytes{namespace=\"${APP_NS}\",container=\"${APP_NS}\"})"}] },
    { "type": "stat", "id": 5, "title": "Pods ready", "gridPos": {"x":20,"y":1,"w":4,"h":4},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"short"}},
      "targets": [{"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
        "expr":"max(kube_deployment_status_replicas_ready{namespace=\"${APP_NS}\",deployment=\"${APP_NS}\"})"}] },
    { "type": "row", "id": 200, "title": "Trends", "gridPos": {"x":0,"y":5,"w":24,"h":1} },
    { "type": "timeseries", "id": 6, "title": "Fleet memory: reserved vs used", "gridPos": {"x":0,"y":6,"w":12,"h":8},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"bytes"}},
      "targets": [
        {"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
         "expr":"sum(kube_pod_container_resource_limits{namespace=\"${APP_NS}\",container=\"${APP_NS}\",resource=\"memory\"})","legendFormat":"reserved (limit x pods)"},
        {"refId":"B","datasource":{"type":"prometheus","uid":"promds"},
         "expr":"sum(container_memory_working_set_bytes{namespace=\"${APP_NS}\",container=\"${APP_NS}\"})","legendFormat":"used (working set)"}] },
    { "type": "timeseries", "id": 7, "title": "Request latency (avg / max)", "gridPos": {"x":12,"y":6,"w":12,"h":8},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"s"}},
      "targets": [
        {"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
         "expr":"sum(rate(http_server_requests_seconds_sum{application=\"${APP_NS}\"}[5m])) / sum(rate(http_server_requests_seconds_count{application=\"${APP_NS}\"}[5m]))","legendFormat":"avg"},
        {"refId":"B","datasource":{"type":"prometheus","uid":"promds"},
         "expr":"max(http_server_requests_seconds_max{application=\"${APP_NS}\"})","legendFormat":"max"}] },
    { "type": "timeseries", "id": 8, "title": "Startup per pod (ready time)", "gridPos": {"x":0,"y":14,"w":12,"h":8},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"s"}},
      "targets": [{"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
        "expr":"perf_sensor_startup_seconds{service=\"${APP_NS}\"}","legendFormat":"{{pod}}"}] },
    { "type": "timeseries", "id": 9, "title": "Working set vs limit (per pod)", "gridPos": {"x":12,"y":14,"w":12,"h":8},
      "datasource": {"type":"prometheus","uid":"promds"}, "fieldConfig": {"defaults":{"unit":"bytes"}},
      "targets": [
        {"refId":"A","datasource":{"type":"prometheus","uid":"promds"},
         "expr":"sum by (pod)(container_memory_working_set_bytes{namespace=\"${APP_NS}\",container=\"${APP_NS}\"})","legendFormat":"working set {{pod}}"},
        {"refId":"B","datasource":{"type":"prometheus","uid":"promds"},
         "expr":"max(kube_pod_container_resource_limits{namespace=\"${APP_NS}\",container=\"${APP_NS}\",resource=\"memory\"})","legendFormat":"limit"}] }
  ]
}
DASH_EOF
kubectl create configmap perf-sensor-dashboard --from-file=perf-sensor.json="${DASH}" -n "${NS}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
  && kubectl label   configmap perf-sensor-dashboard -n "${NS}" grafana_dashboard=1 --overwrite >/dev/null 2>&1 \
  && kubectl annotate configmap perf-sensor-dashboard -n "${NS}" grafana_folder="Workshop Dashboards" --overwrite >/dev/null 2>&1 \
  && log_success "Dashboard 'Java on EKS — Sensor' provisioned" \
  || log_warning "dashboard provisioning skipped (Grafana sidecar / monitoring not present?)"
rm -f "${DASH}"

echo "✅ Success: perf-sensor (image ${REPO}:latest)"
log_info "Reach it from the IDE:"
log_info "  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080 &"
log_info "  curl -s localhost:8090/api/v1/measure/${APP_NS} | jq ."
log_info "Run deploy/java-on-amazon-eks/perf-sensor-ide.sh to install the skills + .mcp.json."
