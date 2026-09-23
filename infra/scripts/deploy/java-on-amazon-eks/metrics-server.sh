#!/bin/bash
# =============================================================================
# metrics-server.sh — Kubernetes Metrics API for the java-on-amazon-eks cluster.
#
# Serves metrics.k8s.io from kubelet stats, which `kubectl top` and eks-node-viewer's
# live CPU/memory column read. Nothing in the sensor, the profiler or the skills uses
# it (they read Prometheus/cAdvisor); it is here for the facilitator's node view.
# Installs cleanly on EKS Auto Mode; no --kubelet-insecure-tls needed. Chart pinned;
# bump METRICS_SERVER_CHART_VERSION to upgrade. Idempotent, non-fatal for the caller.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../../lib/common.sh" ] && source "${SCRIPT_DIR}/../../lib/common.sh"
command -v log_info >/dev/null 2>&1 || {
  log_info()    { echo "ℹ️  $*"; }
  log_success() { echo "✅ $*"; }
  log_warning() { echo "⚠️  $*"; }
  log_error()   { echo "❌ $*" >&2; }
}
LOG="${WORKSHOP_LOG_DIR:-/tmp}/metrics-server.log"

METRICS_SERVER_CHART_VERSION="${METRICS_SERVER_CHART_VERSION:-3.14.0}"   # metrics-server 0.9.0

log_info "Installing metrics-server (chart ${METRICS_SERVER_CHART_VERSION})..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
if helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system --version "${METRICS_SERVER_CHART_VERSION}" \
    --wait --timeout 5m >>"$LOG" 2>&1; then
  log_success "metrics-server installed (kubectl top / eks-node-viewer utilization available)"
else
  log_error "metrics-server install failed — last 20 lines of $LOG:"; tail -n 20 "$LOG"; exit 1
fi
