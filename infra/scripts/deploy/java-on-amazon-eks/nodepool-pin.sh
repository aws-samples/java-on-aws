#!/bin/bash
# =============================================================================
# nodepool-pin.sh — pin the workshop NodePool to one instance family (java-on-amazon-eks only).
#
# setup/eks.sh (shared by every workshop) creates the `workshop` NodePool with broad
# requirements (AMD, c/m category, generation > 5). For java-on-amazon-eks the startup-time numbers
# must be repeatable, so this script narrows the pool to a single family: m6a (AMD EPYC
# Milan, one sustained clock). Otherwise Karpenter can pick a faster-clocked instance
# (e.g. m8azn at 5 GHz) and startup "improves" from hardware, not from the change.
# Family, not type, keeps capacity flexible across sizes.
#
# Replaces the three scheduling requirements (cpu-manufacturer, instance-category,
# instance-generation) with one (instance-family); capacity-type, arch, os, cpu and
# memory requirements stay. Idempotent. Runs after setup/eks.sh.
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

NODEPOOL="${NODEPOOL:-workshop}"
INSTANCE_FAMILY="${INSTANCE_FAMILY:-m6a}"

log_info "Pinning NodePool ${NODEPOOL} to instance family ${INSTANCE_FAMILY}..."
kubectl get nodepool "${NODEPOOL}" >/dev/null 2>&1 || { log_error "NodePool ${NODEPOOL} not found (run setup/eks.sh first)"; exit 1; }

# Rebuild the requirements list: drop the broad selectors, add the family pin once.
PATCH="$(kubectl get nodepool "${NODEPOOL}" -o json | jq -c --arg fam "${INSTANCE_FAMILY}" '
  .spec.template.spec.requirements
  | map(select(.key | IN("eks.amazonaws.com/instance-cpu-manufacturer",
                         "eks.amazonaws.com/instance-category",
                         "eks.amazonaws.com/instance-generation",
                         "eks.amazonaws.com/instance-family") | not))
  + [{"key":"eks.amazonaws.com/instance-family","operator":"In","values":[$fam]}]
  | {spec:{template:{spec:{requirements:.}}}}')"
kubectl patch nodepool "${NODEPOOL}" --type merge -p "${PATCH}" >/dev/null \
  && log_success "NodePool ${NODEPOOL} pinned to ${INSTANCE_FAMILY} (existing nodes drain on consolidation; new nodes are ${INSTANCE_FAMILY})" \
  || { log_error "NodePool patch failed"; exit 1; }
