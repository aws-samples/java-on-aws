#!/bin/bash
# =============================================================================
# Phase 7 — perf-profiler (privilege-free JVM profiler)
#
# Builds and pushes the baked async-profiler image, installs Kyverno and
# metrics-server, and applies the sidecar-injection MutatingPolicy. For the
# builders' session this is pre-run by the bootstrap; an extended lab has
# participants build it step by step.
#
# Runs on the IDE instance as ec2-user with the IDE role. CON405 (EKS-only).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source /etc/profile.d/workshop.sh

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/perf-profiler"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${ECR_REGISTRY}/perf-profiler"

# -----------------------------------------------------------------------------
# 1. Build + push the baked profiler image
#    ECR repo is auto-created on first push (CDK create-on-push template scope
#    includes perf-profiler; IDE role has ecr:* on repository/perf-*).
# -----------------------------------------------------------------------------
log_info "Building and pushing perf-profiler image..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
docker build -t perf-profiler:latest "${APP_DIR}"
docker tag perf-profiler:latest "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"
log_success "perf-profiler image pushed: ${ECR_URI}:latest"

# -----------------------------------------------------------------------------
# 2. Install Kyverno (provides the CEL MutatingPolicy API used by the inject policy)
#    MutatingPolicy (policies.kyverno.io/v1beta1) requires a recent Kyverno.
#    TODO: pin the validated chart version after the first live dry-run.
# -----------------------------------------------------------------------------
log_info "Installing Kyverno..."
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --wait --timeout 10m
log_success "Kyverno installed"

# -----------------------------------------------------------------------------
# 3. Install metrics-server (needed for HPA + eks-node-viewer utilization).
#    Installs cleanly on EKS Auto; no --kubelet-insecure-tls needed.
# -----------------------------------------------------------------------------
log_info "Installing metrics-server..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --wait --timeout 5m
log_success "metrics-server installed"

# -----------------------------------------------------------------------------
# 4. Apply the sidecar-injection MutatingPolicy (image URI substituted in).
# -----------------------------------------------------------------------------
log_info "Applying inject-perf-profiler MutatingPolicy..."
sed "s|__PERF_PROFILER_IMAGE__|${ECR_URI}:latest|g" \
  "${APP_DIR}/k8s/sidecar-inject-policy.yaml" | kubectl apply -f -
log_success "MutatingPolicy inject-perf-profiler applied"

echo "✅ Success: perf-profiler (image ${ECR_URI}:latest; Kyverno + metrics-server + inject policy)"
log_info "Opt a workload in:"
log_info "  kubectl label deploy/<name> -n <ns> perf-profile/sidecar=true --overwrite"
log_info "  kubectl rollout restart deploy/<name> -n <ns>"
