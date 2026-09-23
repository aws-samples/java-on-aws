#!/bin/bash
# =============================================================================
# perf-sensor (bootstrap Phase 7) — deterministic performance sensors for Java
# workloads on EKS, exposed over MCP (streamable-http) + REST. No Bedrock, no Spring AI
# chat, no AWS SDK, no Pod Identity (the sensor makes no AWS calls).
#
# Builds and pushes the image (jib -> ECR, pinned by digest), then applies:
#   - ServiceAccount + read-only ClusterRole (get/list on deployments, pods, pods/log)
#   - Deployment + Service in the monitoring namespace
#   - the "Java on EKS — Sensor" Grafana dashboard (k8s/dashboard.json)
#
# Not app-specific: APP_NS names the workload the dashboard is for; REQUEST_PACKAGE
# names the app's request-path package (the sensor refuses to start without it). Runs
# on the IDE instance as ec2-user with the IDE role.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Optional workshop context (present on the IDE); safe to skip elsewhere.
[ -f "${SCRIPT_DIR}/../../lib/common.sh" ] && source "${SCRIPT_DIR}/../../lib/common.sh"
LOG="${WORKSHOP_LOG_DIR:-/tmp}/perf-sensor-build.log"
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
APP_NS="${APP_NS:-unicorn-store-spring}"                 # namespace == Deployment == container of the workload
REQUEST_PACKAGE="${REQUEST_PACKAGE:-com.unicorn.store}"  # the app's request-path package

# -----------------------------------------------------------------------------
# 1. Build + push the image (the ECR repo is created on first push by the account's
#    creation template, which lists perf-sensor); resolve the pushed digest.
# -----------------------------------------------------------------------------
log_info "Building and pushing perf-sensor image..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_BASE}"
( cd "${APP_DIR}" && mvn -q clean compile jib:build -Dimage="${REPO}:latest" ) >>"$LOG" 2>&1 \
  || { log_error "perf-sensor build failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
DIGEST="$(cat "${APP_DIR}/target/jib-image.digest" 2>/dev/null || true)"
[ -n "${DIGEST}" ] || DIGEST="$(aws ecr describe-images --repository-name perf-sensor --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' --output text --region "${REGION}")"
[ -n "${DIGEST}" ] && [ "${DIGEST}" != "None" ] || { log_error "could not resolve the pushed image digest"; exit 1; }
IMAGE_REF="${REPO}@${DIGEST}"
log_success "perf-sensor image pushed: ${IMAGE_REF}"

# -----------------------------------------------------------------------------
# 2. ServiceAccount + read-only ClusterRole (no write verbs, no Pod Identity).
# -----------------------------------------------------------------------------
log_info "Applying perf-sensor SA + read-only ClusterRole..."
sed "s|__NS__|${NS}|g" "${K8S_DIR}/rbac.yaml" | kubectl apply -f -
log_success "RBAC applied (get/list on deployments, pods, pods/log)"

# -----------------------------------------------------------------------------
# 3. Deployment + Service in the monitoring namespace.
# -----------------------------------------------------------------------------
log_info "Deploying perf-sensor to ${NS} (REQUEST_PACKAGE=${REQUEST_PACKAGE})..."
sed -e "s|__IMAGE__|${IMAGE_REF}|g" -e "s|__NS__|${NS}|g" -e "s|__REQUEST_PACKAGE__|${REQUEST_PACKAGE}|g" \
  "${K8S_DIR}/deployment.yaml" | kubectl apply -f -

# The image is pinned by digest, so a changed image is a changed pod template: no
# rollout restart needed.
kubectl -n "${NS}" rollout status deploy/perf-sensor --timeout=200s || {
  log_error "rollout not ready; recent logs:"; kubectl -n "${NS}" logs -l app=perf-sensor --tail=60; exit 1; }

# -----------------------------------------------------------------------------
# 4. Grafana dashboard (k8s/dashboard.json, __APP_NS__ substituted) shipped as a
#    ConfigMap the Grafana sidecar imports (label grafana_dashboard=1, folder from the
#    grafana_folder annotation).
# -----------------------------------------------------------------------------
log_info "Provisioning 'Java on EKS — Sensor' dashboard..."
DASH=$(mktemp)
sed "s|__APP_NS__|${APP_NS}|g" "${K8S_DIR}/dashboard.json" > "${DASH}"
kubectl create configmap perf-sensor-dashboard --from-file=perf-sensor.json="${DASH}" -n "${NS}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
  && kubectl label   configmap perf-sensor-dashboard -n "${NS}" grafana_dashboard=1 --overwrite >/dev/null 2>&1 \
  && kubectl annotate configmap perf-sensor-dashboard -n "${NS}" grafana_folder="Workshop Dashboards" --overwrite >/dev/null 2>&1 \
  && log_success "Dashboard 'Java on EKS — Sensor' provisioned" \
  || log_warning "dashboard provisioning skipped (Grafana sidecar / monitoring not present?)"
rm -f "${DASH}"

echo "✅ Success: perf-sensor (image ${IMAGE_REF})"
log_info "Reach it from the IDE:"
log_info "  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080 &"
log_info "  curl -s localhost:8090/api/v1/measure/${APP_NS} | jq ."
log_info "Run deploy/java-on-amazon-eks/perf-sensor-ide.sh to install the skills + .mcp.json."
