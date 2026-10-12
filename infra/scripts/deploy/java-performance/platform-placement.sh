#!/bin/bash
# =============================================================================
# platform-placement.sh — keep the platform off the application's node (java-performance only).
#
# The app selects the `workshop` NodePool (karpenter.sh/nodepool: workshop). The platform
# workloads have no selector, so Karpenter places them wherever there is room, usually on
# the app's 4-vCPU node. There the app shares physical cores (SMT) with Prometheus,
# Pyroscope and Kyverno, and the session's measurements move with that load (startup and
# steady CPU 10–60 % higher in a test run). This script pins every platform Deployment and
# StatefulSet to the Auto Mode built-in `general-purpose` NodePool, so the `workshop` node
# carries only the app and the DaemonSets. The app manifest is unchanged.
#
# Namespaces: monitoring (Prometheus, Grafana, Pyroscope, Alloy, sensor), kyverno,
# kube-startup-cpu-boost-system, and metrics-server in kube-system. Pods move once, at
# bootstrap; Prometheus, Grafana and Pyroscope keep their data on their PVCs. The pods are
# marked do-not-disrupt, so consolidation does not move them later.
# Idempotent. Run after the platform installs (template stage E). A later `helm upgrade`
# of one of these releases drops the selector: run this script again afterwards.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

POOL="${PLATFORM_NODEPOOL:-general-purpose}"
kubectl get nodepool "${POOL}" >/dev/null 2>&1 || { log_error "NodePool ${POOL} not found (EKS Auto Mode built-in pools disabled?)"; exit 1; }

# do-not-disrupt: the general-purpose pool consolidates underutilized nodes after 30 s. A
# consolidation during the session would move the sensor or Kyverno in the middle of a
# checklist or an admission; the annotation keeps their nodes until the pods go.
PATCH="{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"karpenter.sh/do-not-disrupt\":\"true\"}},\"spec\":{\"nodeSelector\":{\"karpenter.sh/nodepool\":\"${POOL}\"}}}}}"
RC=0
pin() {   # pin NAMESPACE KIND/NAME...
    local ns="$1"; shift
    for w in "$@"; do
        if kubectl -n "${ns}" patch "${w}" --type merge -p "${PATCH}" >/dev/null; then
            log_info "${ns}/${w} → ${POOL}"
        else
            log_error "patch failed: ${ns}/${w}"; RC=1
        fi
    done
}

for ns in monitoring kyverno kube-startup-cpu-boost-system; do
    kubectl get namespace "${ns}" >/dev/null 2>&1 || { log_warning "namespace ${ns} not found, skipped"; continue; }
    mapfile -t W < <(kubectl -n "${ns}" get deployment,statefulset -o name)
    [ "${#W[@]}" -gt 0 ] && pin "${ns}" "${W[@]}"
done
kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1 && pin kube-system deployment/metrics-server

for ns in monitoring kyverno kube-startup-cpu-boost-system; do
    kubectl get namespace "${ns}" >/dev/null 2>&1 || continue
    for w in $(kubectl -n "${ns}" get deployment,statefulset -o name); do
        kubectl -n "${ns}" rollout status "${w}" --timeout=600s >/dev/null || { log_error "${ns}/${w} not ready on ${POOL}"; RC=1; }
    done
done

[ "${RC}" -eq 0 ] && log_success "Platform workloads on NodePool ${POOL}; the workshop node carries the app only" || exit 1
