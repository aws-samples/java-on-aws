#!/bin/bash
# =============================================================================
# perf-profiler (bootstrap Phase 6) — privilege-free JVM profiler sidecar
#
# Builds and pushes the baked async-profiler image, installs Kyverno, and applies
# the sidecar-injection MutatingPolicy with the image pinned BY DIGEST (the tag is
# mutable; the digest is what was just pushed). For the builders' session this is
# pre-run by the bootstrap; an extended lab has participants build it step by step.
#
# Runs on the IDE instance as ec2-user with the IDE role. Not app-specific: the
# workload opts in with a label; APP_UID must match the UID the app image runs as
# (JVM dynamic attach needs the same UID; the workshop app uses 1000).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
LOG="${WORKSHOP_LOG_DIR}/perf-profiler.log"
# Optional workshop context (present on the IDE); safe to skip elsewhere (e.g. a Mac).
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/perf-profiler"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${ECR_REGISTRY}/perf-profiler"
CLUSTER_NAME="${PREFIX:-workshop}-eks"                 # stamped into the sidecar as a Pyroscope label
APP_UID="${APP_UID:-1000}"                             # UID the profiled app runs as
PYROSCOPE_URL="${PYROSCOPE_URL:-http://pyroscope.monitoring:4040}"
KYVERNO_CHART_VERSION="3.9.1"                          # Kyverno v1.19.1; MutatingPolicy v1beta1 needs >= this

# -----------------------------------------------------------------------------
# 1. Build + push the baked profiler image; resolve the pushed digest.
#    The ECR repo is auto-created on first push (CDK create-on-push template scope
#    includes perf-profiler; the IDE role has ecr:* on repository/perf-*).
# -----------------------------------------------------------------------------
log_info "Building and pushing perf-profiler image..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
# Pin linux/amd64: the EKS nodes are amd64, but this build may run on an arm64 host
# (e.g. an Apple-Silicon Mac), where a native `docker build` would push arm64 and the
# nodes fail the pull with "no match for platform".
docker build --platform linux/amd64 -t perf-profiler:latest "${APP_DIR}" >>"$LOG" 2>&1 || { log_error "perf-profiler docker build failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
docker tag perf-profiler:latest "${ECR_URI}:latest"
docker push "${ECR_URI}:latest" >>"$LOG" 2>&1 || { log_error "perf-profiler docker push failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
DIGEST="$(aws ecr describe-images --repository-name perf-profiler --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' --output text --region "${AWS_REGION}")"
[ -n "${DIGEST}" ] && [ "${DIGEST}" != "None" ] || { log_error "could not resolve the pushed image digest"; exit 1; }
IMAGE_REF="${ECR_URI}@${DIGEST}"
log_success "perf-profiler image pushed: ${IMAGE_REF}"

# -----------------------------------------------------------------------------
# 2. Install Kyverno (provides the CEL MutatingPolicy API used by the inject policy).
# -----------------------------------------------------------------------------
log_info "Installing Kyverno ${KYVERNO_CHART_VERSION}..."
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace --version "${KYVERNO_CHART_VERSION}" \
  --wait --timeout 10m >>"$LOG" 2>&1 || { log_error "kyverno helm install failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
log_success "Kyverno installed"

# -----------------------------------------------------------------------------
# 3. Apply the sidecar-injection MutatingPolicy (placeholders substituted).
# -----------------------------------------------------------------------------
log_info "Applying inject-perf-profiler MutatingPolicy (image ${IMAGE_REF}, app UID ${APP_UID})..."
sed -e "s|__PERF_PROFILER_IMAGE__|${IMAGE_REF}|g" \
    -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
    -e "s|__APP_UID__|${APP_UID}|g" \
    -e "s|__PYROSCOPE_URL__|${PYROSCOPE_URL}|g" \
  "${APP_DIR}/k8s/sidecar-inject-policy.yaml" | kubectl apply -f -
log_success "MutatingPolicy inject-perf-profiler applied"

echo "✅ Success: perf-profiler (image ${IMAGE_REF}; Kyverno + inject policy)"
log_info "Opt a workload in (declarative — survives redeploy/GitOps):"
log_info "  add 'perf-profile/sidecar: \"true\"' under spec.template.metadata.labels in the deployment manifest, then:"
log_info "  kubectl apply -f <deployment>.yaml   # pod-template change rolls the pods; sidecar injects"
