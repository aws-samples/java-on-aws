#!/bin/bash
# =============================================================================
# platform-placement.sh — keep the platform off the application's node (java-performance only).
#
# The app selects the `workshop` NodePool (karpenter.sh/nodepool: workshop). The platform
# workloads have no selector, so Karpenter places them wherever there is room, usually on
# the app's 4-vCPU node. There the app shares physical cores (SMT) with Prometheus,
# Pyroscope and Kyverno, and the session's measurements move with that load (startup and
# steady CPU 10–60 % higher in a test run). This script creates a `platform` NodePool and
# pins every platform Deployment and StatefulSet to it, so the `workshop` node carries only
# the app and the DaemonSets. The app manifest is unchanged.
#
# The pool admits only instances with at least 4 vCPU and 8 GiB (c6a.xlarge is the cheapest
# match): the platform requests about 1.5 vCPU and 4.4 GiB, so one node holds all of it. On
# the built-in general-purpose pool Karpenter started a c6a.large per batch of pending pods
# and kept two (do-not-disrupt blocks the merge), at more cost than one c6a.xlarge.
#
# Namespaces: monitoring (Prometheus, Grafana, Pyroscope, Alloy, sensor), kyverno,
# kube-startup-cpu-boost-system, and metrics-server in kube-system. Pods move once, at
# bootstrap; Prometheus, Grafana and Pyroscope keep their data on their PVCs. The pods are
# marked do-not-disrupt and the pool consolidates only when empty, so nothing moves them later.
# Idempotent. `platform-placement.sh pool` creates only the NodePool (template stage B, so
# monitoring.sh installs onto it via MONITORING_NODEPOOL); without an argument it also pins
# the workloads (after stage E). A later `helm upgrade`
# of one of these releases drops the selector: run this script again afterwards.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

POOL="${PLATFORM_NODEPOOL:-platform}"

kubectl apply -f - <<EOF >/dev/null || { log_error "NodePool ${POOL} could not be created"; exit 1; }
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ${POOL}
spec:
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: eks.amazonaws.com/instance-category
          operator: In
          values: ["c", "m"]
        - key: eks.amazonaws.com/instance-generation
          operator: Gt
          values: ["5"]
        - key: eks.amazonaws.com/instance-cpu
          operator: Gt
          values: ["3"]
        - key: eks.amazonaws.com/instance-memory
          operator: Gt
          values: ["8000"]
  limits:
    cpu: "16"
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5m
EOF
log_info "NodePool ${POOL}: at least 4 vCPU and 8 GiB, consolidation WhenEmpty"
# `pool`: only the NodePool (template stage B, before monitoring.sh installs onto it).
[ "${1:-}" = pool ] && exit 0

# do-not-disrupt: a consolidation during the session would move the sensor or Kyverno in
# the middle of a checklist or an admission; the annotation keeps their node until the pods go.
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
