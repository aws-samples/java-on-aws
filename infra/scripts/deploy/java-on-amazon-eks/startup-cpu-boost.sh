#!/bin/bash
# =============================================================================
# Kube Startup CPU Boost — cluster-wide (platform) install.
#
# This is the PRODUCTION path for the optimization skill's "start faster without
# changing the image" answer. It installs a controller + mutating webhook + CRD
# (cluster-admin, ONCE) so that a developer only writes a namespaced
# `StartupCPUBoost` CR: the controller then boosts CPU at pod admission and resizes
# it back DOWN in place once the pod is Ready — automatically, for every pod, every
# rollout, every scale-up. No per-pod `kubectl patch` (that manual path is only for
# teaching the underlying in-place-resize primitive).
#
# Cluster-scoped objects (CRD, ClusterRole, webhooks) require cluster-admin, which is
# why this lives in the bootstrap (platform layer), not in participant/dev steps.
#
# Upstream: https://github.com/google/kube-startup-cpu-boost
# Version is pinned; bump BOOST_VERSION to adopt a newer release.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../../lib/common.sh" ] && source "${SCRIPT_DIR}/../../lib/common.sh"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh
command -v log_info >/dev/null 2>&1 || {
  log_info()    { echo "ℹ️  $*"; }
  log_success() { echo "✅ $*"; }
  log_warning() { echo "⚠️  $*"; }
  log_error()   { echo "❌ $*" >&2; }
}

BOOST_VERSION="v0.21.1"
MANIFEST="https://github.com/google/kube-startup-cpu-boost/releases/download/${BOOST_VERSION}/manifests.yaml"
NS="kube-startup-cpu-boost-system"

log_info "Installing Kube Startup CPU Boost ${BOOST_VERSION} (cluster-wide controller + webhook)..."
# --server-side: the bundled CRD is large; client-side apply can exceed the
# last-applied annotation size limit.
if kubectl apply --server-side --force-conflicts -f "${MANIFEST}"; then
  kubectl -n "${NS}" rollout status deploy/kube-startup-cpu-boost-controller-manager --timeout=180s \
    && log_success "Kube Startup CPU Boost ${BOOST_VERSION} installed (controller Ready)" \
    || log_warning "Boost controller applied but not Ready yet (webhook may lag; the CR still admits later)"
else
  log_warning "Kube Startup CPU Boost install failed — the skill's manual in-place-resize path still works"
fi
