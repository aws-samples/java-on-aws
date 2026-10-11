#!/bin/bash
# =============================================================================
# perf-sensor.sh [build|install] — deterministic performance sensors for Java
# workloads on EKS, exposed over MCP (streamable-http) + REST. No Bedrock, no Spring AI
# chat, no AWS SDK, no Pod Identity (the sensor makes no AWS calls).
#
#   build    jib build + push to ECR, record the digest (no cluster needed)
#   install  ServiceAccount + read-only ClusterRole, the checklist rules ConfigMap,
#            Deployment (image by digest) + Service in the monitoring namespace, the
#            Grafana dashboard, and the IDE's port-forward localhost:8090 -> the sensor as
#            the systemd service perf-sensor-port-forward (Restart=always, as ec2-user)
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
SENSOR_SERVICES="${SENSOR_SERVICES:-${APP_NS}}"          # workloads the sensor answers for (request package above)

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

  # The checklist rules (CEL) as a ConfigMap the sensor reads at startup, so anyone can
  # see what is scored: kubectl -n monitoring get cm perf-sensor-checklist-rules -o yaml
  local rules="${APP_DIR}/src/main/resources/checklist-rules.yaml" rules_sha
  log_info "Applying checklist rules ConfigMap..."
  kubectl create configmap perf-sensor-checklist-rules --from-file=checklist-rules.yaml="${rules}" -n "${NS}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null \
    || { log_error "could not apply ConfigMap perf-sensor-checklist-rules"; exit 1; }
  rules_sha="$(sha256sum "${rules}" | cut -c1-16)"

  log_info "Deploying perf-sensor to ${NS} (REQUEST_PACKAGE=${REQUEST_PACKAGE})..."
  sed -e "s|__IMAGE__|${image_ref}|g" -e "s|__NS__|${NS}|g" -e "s|__REQUEST_PACKAGE__|${REQUEST_PACKAGE}|g" -e "s|__SENSOR_SERVICES__|${SENSOR_SERVICES}|g" \
    -e "s|__RULES_SHA__|${rules_sha}|g" "${K8S_DIR}/deployment.yaml" | kubectl apply -f - >/dev/null
  # The image is pinned by digest and the rules by hash, so a changed image or rules file
  # is a changed pod template: no rollout restart needed.
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

  port_forward_service

  echo "✅ Success: perf-sensor (image ${image_ref})"
  log_info "Reach it from the IDE:  curl -s localhost:8090/api/v1/measure/${APP_NS} | jq .   (systemd: ${PF_UNIT})"
}

# localhost:8090 on the IDE -> svc/perf-sensor:8080, for Claude Code (.mcp.json) and curl.
# kubectl port-forward ends whenever the sensor pod is replaced; systemd starts it again,
# so nobody keeps a terminal open for it. A login shell gives kubectl the user's PATH,
# kubeconfig and /etc/profile.d/workshop.sh (region for `aws eks get-token`).
PF_UNIT="perf-sensor-port-forward"
port_forward_service() {
  log_info "Installing the IDE port-forward (systemd ${PF_UNIT}, localhost:8090)..."
  sudo tee "/etc/systemd/system/${PF_UNIT}.service" >/dev/null <<EOF
[Unit]
Description=Port-forward localhost:8090 to svc/perf-sensor:8080 in ${NS}
After=network-online.target
Wants=network-online.target

[Service]
User=$(id -un)
ExecStart=/bin/bash -lc 'exec kubectl -n ${NS} port-forward --address 127.0.0.1 svc/perf-sensor 8090:8080'
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable "${PF_UNIT}" >/dev/null 2>&1
  sudo systemctl restart "${PF_UNIT}"
  for _ in $(seq 1 15); do
    curl -sf localhost:8090/actuator/health >/dev/null 2>&1 && { log_success "port-forward up: localhost:8090"; return 0; }
    sleep 2
  done
  log_warning "localhost:8090 not answering yet (journalctl -u ${PF_UNIT})"
}

case "${1:-all}" in
  build)   build ;;
  install) install ;;
  all)     build; install ;;
  *)       echo "usage: $0 [build|install]" >&2; exit 2 ;;
esac
