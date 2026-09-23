#!/bin/bash
# =============================================================================
# app-prepare.sh — the participant's starting point, without a cluster.
#
# Produces ~/environment/unicorn-store-spring at the commit
# "Starting point: containerized + deployed to EKS" and the :latest image in ECR:
#   1. copy apps/unicorn-store-spring, drop src/test, de-spoil (remove the org.crac
#      dependency and the finished CRaC hook UnicornPublisher.crac — the CRaC step is
#      discovered in the session, not handed over)
#   2. lay the end state of the immersion-day containerize + deploy pages over it
#      (app/Dockerfile, app/k8s/*.yaml with the account's ECR URI filled in)
#   3. build and push the image (:latest)
#   4. git init, one "Initial commit" (sources), one "Starting point" commit
#      (Dockerfile + manifests) — the same two commits the replayed labs produced
#
# Needs Docker, Maven, ECR and the IDE role; no kubectl. Runs in the bootstrap while
# the EKS cluster is still being created. Idempotent: an existing copy is replaced.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh
LOG="${WORKSHOP_LOG_DIR}/app-prepare.log"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_NAME="unicorn-store-spring"
SRC="${REPO_ROOT}/apps/${APP_NAME}"
OVERLAY="${SCRIPT_DIR}/app"
DST="${HOME}/environment/${APP_NAME}"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${ECR_REGISTRY}/${APP_NAME}"
START_MSG="Starting point: containerized + deployed to EKS"

git config --global user.name  >/dev/null 2>&1 || git config --global user.name "Workshop User"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "user@sample.com"

# 1. Sources
log_info "Preparing ${DST} from ${SRC}..."
rm -rf "${DST}"
mkdir -p "${HOME}/environment"
cp -r "${SRC}" "${DST}"
rm -rf "${DST}/src/test" "${DST}/target"
# De-spoil: the whole <dependencies> block that carries org.crac (only crac lives there).
perl -0777 -i -pe 's{\s*<dependencies>\s*<dependency>\s*<groupId>org\.crac</groupId>.*?</dependencies>}{}s' "${DST}/pom.xml"
find "${DST}/src" -name '*.crac' -delete
( cd "${DST}" && git init -q -b main && git add -A && git commit -q -m "Initial commit" )
log_success "Sources copied, de-spoiled, initial commit made"

# 2. Containerize + deploy end state
cp "${OVERLAY}/Dockerfile" "${DST}/Dockerfile"
mkdir -p "${DST}/k8s"
for f in "${OVERLAY}"/k8s/*.yaml; do
  sed "s|__ECR_URI__|${ECR_URI}|g" "$f" > "${DST}/k8s/$(basename "$f")"
done
log_success "Dockerfile + k8s manifests in place (image ${ECR_URI}:latest)"

# 3. Image
log_info "Ensuring ECR repository ${APP_NAME} exists..."
aws ecr describe-repositories --repository-names "${APP_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "${APP_NAME}" --region "${AWS_REGION}" >/dev/null
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}" >/dev/null 2>&1
log_info "Building ${APP_NAME}:latest (full log: ${LOG})..."
( cd "${DST}" && docker build -t "${ECR_URI}:latest" . ) >>"${LOG}" 2>&1 \
  || { log_error "docker build failed — last 40 lines of ${LOG}:"; tail -n 40 "${LOG}"; exit 1; }
docker push "${ECR_URI}:latest" >>"${LOG}" 2>&1 \
  || { log_error "docker push failed — last 40 lines of ${LOG}:"; tail -n 40 "${LOG}"; exit 1; }
log_success "Pushed ${ECR_URI}:latest"

# 4. Starting-point commit
( cd "${DST}" && git add -A && git commit -q -m "${START_MSG}" )
log_success "Committed '${START_MSG}'"

echo "✅ Success: unicorn-store-spring starting point (sources, image, manifests)"
