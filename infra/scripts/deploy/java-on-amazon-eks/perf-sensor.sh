#!/bin/bash
# =============================================================================
# perf-sensor.sh [build|install] — deterministic performance sensors for Java
# workloads on EKS, exposed over MCP (streamable-http) + REST. No Bedrock, no Spring AI
# chat, no AWS SDK, no Pod Identity (the sensor makes no AWS calls).
#
#   build    jib build + push to ECR, record the digest (no cluster needed)
#   install  ServiceAccount + read-only ClusterRole, Deployment (image by digest) +
#            Service in the monitoring namespace, the Grafana dashboard
#   (none)   both, in order
#
# Not app-specific: APP_NS names the workload the dashboard is for; REQUEST_PACKAGE
# names the app's request-path package (the sensor refuses to start without it). Runs
# on the IDE instance as ec2-user with the IDE role.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../../lib/common.sh" ] && source "${SCRIPT_DIR}/../../lib/common.sh"
LOG="${WORKSHOP_LOG_DIR:-/tmp}/perf-sensor-build.log"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh
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
STATE_DIR="${WORKSHOP_STATE_DIR:-${HOME}/.workshop}"
IMAGE_FILE="${STATE_DIR}/perf-sensor.image"
NS="monitoring"
APP_NS="${APP_NS:-unicorn-store-spring}"                 # namespace == Deployment == container of the workload
REQUEST_PACKAGE="${REQUEST_PACKAGE:-com.unicorn.store}"  # the app's request-path package

build() {
  # The ECR repo is normally created on first push by the account's creation template,
  # but a stack deployed before perf-sensor was added to that template has no repo and
  # jib fails with 404 NAME_UNKNOWN — so create it idempotently first.
  log_info "Ensuring ECR repository perf-sensor exists..."
  aws ecr describe-repositories --repository-names perf-sensor --region "${REGION}" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name perf-sensor --region "${REGION}" >/dev/null \
    || { log_error "could not create ECR repo perf-sensor"; exit 1; }
  log_info "Building and pushing perf-sensor image (full log: ${LOG})..."
  aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${ECR_BASE}" >/dev/null 2>&1
  ( cd "${APP_DIR}" && mvn -q clean compile jib:build -Dimage="${REPO}:latest" ) >>"$LOG" 2>&1 \
    || { log_error "perf-sensor build failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
  local digest
  digest="$(cat "${APP_DIR}/target/jib-image.digest" 2>/dev/null || true)"
  [ -n "${digest}" ] || digest="$(aws ecr describe-images --repository-name perf-sensor --image-ids imageTag=latest \
    --query 'imageDetails[0].imageDigest' --output text --region "${REGION}")"
  [ -n "${digest}" ] && [ "${digest}" != "None" ] || { log_error "could not resolve the pushed image digest"; exit 1; }
  mkdir -p "${STATE_DIR}"
  echo "${REPO}@${digest}" > "${IMAGE_FILE}"
  log_success "perf-sensor image pushed: $(cat "${IMAGE_FILE}")"
}

install() {
  local image_ref
  image_ref="$(cat "${IMAGE_FILE}" 2>/dev/null || true)"
  if [ -z "${image_ref}" ]; then
    image_ref="${REPO}@$(aws ecr describe-images --repository-name perf-sensor --image-ids imageTag=latest \
      --query 'imageDetails[0].imageDigest' --output text --region "${REGION}")"
  fi
  case "${image_ref}" in *@sha256:*) ;; *) log_error "no perf-sensor image found — run '$0 build' first"; exit 1;; esac

  log_info "Applying perf-sensor SA + read-only ClusterRole..."
  sed "s|__NS__|${NS}|g" "${K8S_DIR}/rbac.yaml" | kubectl apply -f - >/dev/null
  log_success "RBAC applied (get/list on deployments, pods, pods/log)"

  log_info "Deploying perf-sensor to ${NS} (REQUEST_PACKAGE=${REQUEST_PACKAGE})..."
  sed -e "s|__IMAGE__|${image_ref}|g" -e "s|__NS__|${NS}|g" -e "s|__REQUEST_PACKAGE__|${REQUEST_PACKAGE}|g" \
    "${K8S_DIR}/deployment.yaml" | kubectl apply -f - >/dev/null
  # The image is pinned by digest, so a changed image is a changed pod template: no
  # rollout restart needed.
  kubectl -n "${NS}" rollout status deploy/perf-sensor --timeout=200s >/dev/null || {
    log_error "rollout not ready; recent logs:"; kubectl -n "${NS}" logs -l app=perf-sensor --tail=60; exit 1; }
  log_success "perf-sensor running (${image_ref})"

  # Grafana dashboard (k8s/dashboard.json, __APP_NS__ substituted) shipped as a ConfigMap
  # the Grafana sidecar imports (label grafana_dashboard=1, folder from the annotation).
  log_info "Provisioning 'Java on EKS — Sensor' dashboard..."
  local dash
  dash=$(mktemp)
  sed "s|__APP_NS__|${APP_NS}|g" "${K8S_DIR}/dashboard.json" > "${dash}"
  kubectl create configmap perf-sensor-dashboard --from-file=perf-sensor.json="${dash}" -n "${NS}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
    && kubectl label   configmap perf-sensor-dashboard -n "${NS}" grafana_dashboard=1 --overwrite >/dev/null 2>&1 \
    && kubectl annotate configmap perf-sensor-dashboard -n "${NS}" grafana_folder="Workshop Dashboards" --overwrite >/dev/null 2>&1 \
    && log_success "Dashboard 'Java on EKS — Sensor' provisioned" \
    || log_warning "dashboard provisioning skipped (Grafana sidecar / monitoring not present?)"
  rm -f "${dash}"

  echo "✅ Success: perf-sensor (image ${image_ref})"
  log_info "Reach it from the IDE:  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080 &  then  curl -s localhost:8090/api/v1/measure/${APP_NS} | jq ."
}

case "${1:-all}" in
  build)   build ;;
  install) install ;;
  all)     build; install ;;
  *)       echo "usage: $0 [build|install]" >&2; exit 2 ;;
esac
