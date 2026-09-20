#!/bin/bash
# =============================================================================
# Phase 8b — prebuild the optimized unicorn-store-spring images (:crac, :aot)
#
# The builders' session applies the optimizer's CRaC/AOT Dockerfile artifact and
# deploys the result. A CRaC/AOT build (Maven + training/checkpoint run against
# Aurora) takes several minutes, so the bootstrap prebuilds both tags into ECR.
# Participants still save the artifact and can build it themselves; the prebuilt
# tag is what they deploy without waiting.
#
# Builds from a throwaway copy of the participant's app dir so the workshop
# starting point (~/environment/unicorn-store-spring) stays untouched. Uses the
# golden Dockerfiles from apps/dockerfiles and swaps in the CRaC Resource hook
# (UnicornPublisher.crac) for the checkpoint build.
#
# Runs on the IDE instance (amd64, inside the VPC so the DB is reachable).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source /etc/profile.d/workshop.sh

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_SRC="${HOME}/environment/unicorn-store-spring"
GOLDEN_DIR="${REPO_ROOT}/apps/dockerfiles"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/unicorn-prebuild.XXXXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

[ -d "${APP_SRC}" ] || { log_error "App dir not found: ${APP_SRC} (run Phase 3 first)"; exit 1; }
[ -x "${APP_SRC}/scripts/build.sh" ] || { log_error "scripts/build.sh missing in ${APP_SRC}"; exit 1; }

log_info "Copying app to ${BUILD_DIR} for the prebuild..."
cp -r "${APP_SRC}/." "${BUILD_DIR}/"
rm -rf "${BUILD_DIR}/.git" "${BUILD_DIR}/target"

# --- CRaC: golden Dockerfile + Resource hook swapped in ----------------------
log_info "Prebuilding unicorn-store-spring:crac..."
cp "${GOLDEN_DIR}/Dockerfile.08-crac" "${BUILD_DIR}/Dockerfile.crac"
PUBLISHER_DIR="${BUILD_DIR}/src/main/java/com/unicorn/store/data"
if [ -f "${PUBLISHER_DIR}/UnicornPublisher.crac" ]; then
    cp "${PUBLISHER_DIR}/UnicornPublisher.crac" "${PUBLISHER_DIR}/UnicornPublisher.java"
else
    # Hard-fail here rather than let the checkpoint fail silently: without the hook
    # (and the org.crac dep it implies) the CRaC checkpoint never writes /opt/crac-files,
    # and the build dies 20 lines later with a cryptic `COPY "/opt/crac-files": not found`.
    # A missing hook means the source was de-spoiled before this ran — fix the phase order.
    log_error "UnicornPublisher.crac not found in ${PUBLISHER_DIR} — source is de-spoiled; prebuild must run BEFORE de-spoil"
    exit 1
fi
( cd "${BUILD_DIR}" && ./scripts/build.sh crac Dockerfile.crac ) \
    && log_success "unicorn-store-spring:crac pushed" \
    || { log_error "CRaC prebuild failed"; exit 1; }

# --- AOT: golden Dockerfile on the unmodified source --------------------------
log_info "Prebuilding unicorn-store-spring:aot..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -r "${APP_SRC}/." "${BUILD_DIR}/"
rm -rf "${BUILD_DIR}/.git" "${BUILD_DIR}/target"
cp "${GOLDEN_DIR}/Dockerfile.06-aot" "${BUILD_DIR}/Dockerfile.aot"
( cd "${BUILD_DIR}" && ./scripts/build.sh aot Dockerfile.aot ) \
    && log_success "unicorn-store-spring:aot pushed" \
    || { log_error "AOT prebuild failed"; exit 1; }

log_success "Prebuilt images ready: unicorn-store-spring:{crac,aot}"
