#!/bin/bash
# =============================================================================
# perf-profiler.sh [build|install] — privilege-free JVM profiler sidecar
#
#   build    build + push the baked async-profiler image, record its digest
#            (no cluster needed; runs while EKS is still being created)
#   install  install Kyverno and apply the sidecar-injection MutatingPolicy with the
#            image pinned BY DIGEST (the tag is mutable; the digest is what was pushed)
#   (none)   both, in order
#
# Runs on the IDE instance as ec2-user with the IDE role. Not app-specific: the
# workload opts in with a label; APP_UID must match the UID the app image runs as
# (JVM dynamic attach needs the same UID; the workshop app uses 1000).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
LOG="${WORKSHOP_LOG_DIR}/perf-profiler.log"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/perf-profiler"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${ECR_REGISTRY}/perf-profiler"
STATE_DIR="${WORKSHOP_STATE_DIR:-${HOME}/.workshop}"
IMAGE_FILE="${STATE_DIR}/perf-profiler.image"           # build writes, install reads
CLUSTER_NAME="${PREFIX:-workshop}-eks"                 # stamped into the sidecar as a Pyroscope label
APP_UID="${APP_UID:-1000}"                             # UID the profiled app runs as
PYROSCOPE_URL="${PYROSCOPE_URL:-http://pyroscope.monitoring:4040}"
KYVERNO_CHART_VERSION="3.9.1"                          # Kyverno v1.19.1; MutatingPolicy v1beta1 needs >= this

build() {
  log_info "Building and pushing perf-profiler image..."
  aws ecr describe-repositories --repository-names perf-profiler --region "${AWS_REGION}" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name perf-profiler --region "${AWS_REGION}" >/dev/null
  aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_REGISTRY}" >/dev/null 2>&1
  # Pin linux/amd64: the EKS nodes are amd64, but this build may run on an arm64 host
  # (e.g. an Apple-Silicon Mac), where a native `docker build` would push arm64 and the
  # nodes fail the pull with "no match for platform".
  docker build --platform linux/amd64 -t "${ECR_URI}:latest" "${APP_DIR}" >>"$LOG" 2>&1 \
    || { log_error "perf-profiler docker build failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
  docker push "${ECR_URI}:latest" >>"$LOG" 2>&1 \
    || { log_error "perf-profiler docker push failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
  local digest
  digest="$(aws ecr describe-images --repository-name perf-profiler --image-ids imageTag=latest \
    --query 'imageDetails[0].imageDigest' --output text --region "${AWS_REGION}")"
  [ -n "${digest}" ] && [ "${digest}" != "None" ] || { log_error "could not resolve the pushed image digest"; exit 1; }
  mkdir -p "${STATE_DIR}"
  echo "${ECR_URI}@${digest}" > "${IMAGE_FILE}"
  log_success "perf-profiler image pushed: $(cat "${IMAGE_FILE}")"
}

install() {
  local image_ref
  image_ref="$(cat "${IMAGE_FILE}" 2>/dev/null || true)"
  if [ -z "${image_ref}" ]; then
    image_ref="${ECR_URI}@$(aws ecr describe-images --repository-name perf-profiler --image-ids imageTag=latest \
      --query 'imageDetails[0].imageDigest' --output text --region "${AWS_REGION}")"
  fi
  case "${image_ref}" in *@sha256:*) ;; *) log_error "no perf-profiler image found — run '$0 build' first"; exit 1;; esac

  log_info "Installing Kyverno ${KYVERNO_CHART_VERSION}..."
  helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno --create-namespace --version "${KYVERNO_CHART_VERSION}" \
    --wait --timeout 10m >>"$LOG" 2>&1 || { log_error "kyverno helm install failed — last 40 lines of $LOG:"; tail -n 40 "$LOG"; exit 1; }
  log_success "Kyverno installed"

  log_info "Applying inject-perf-profiler MutatingPolicy (image ${image_ref}, app UID ${APP_UID})..."
  sed -e "s|__PERF_PROFILER_IMAGE__|${image_ref}|g" \
      -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
      -e "s|__APP_UID__|${APP_UID}|g" \
      -e "s|__PYROSCOPE_URL__|${PYROSCOPE_URL}|g" \
    "${APP_DIR}/k8s/sidecar-inject-policy.yaml" | kubectl apply -f - >/dev/null
  log_success "MutatingPolicy inject-perf-profiler applied"

  echo "✅ Success: perf-profiler (image ${image_ref}; Kyverno + inject policy)"
  log_info "Opt a workload in: add 'perf-profile/sidecar: \"true\"' under spec.template.metadata.labels and kubectl apply the Deployment"
}

case "${1:-all}" in
  build)   build ;;
  install) install ;;
  all)     build; install ;;
  *)       echo "usage: $0 [build|install]" >&2; exit 2 ;;
esac
