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
# generic Dockerfiles the optimization skill hands to participants
# (apps/perf-sensor/skills/java-on-eks-optimization/references/Dockerfile.{crac,aot}),
# with their ARGs filled via build-args, so the prebuilt tag is byte-for-byte what a
# participant's own build of the skill's artifact produces. The CRaC checkpoint bakes
# GC, heap bounds and the processor count in, so JAVA_HEAP_OPTS must match the memory
# limit module 1 lands on (sizing-policy.yaml: 640Mi -> -Xmx480m -Xms320m) and
# JAVA_CPU_OPTS the CPU limit (1). Swaps in the CRaC Resource hook
# (UnicornPublisher.crac) for the checkpoint build.
#
# Runs on the IDE instance (amd64, inside the VPC so the DB is reachable).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source /etc/profile.d/workshop.sh

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_SRC="${APP_SRC:-${HOME}/environment/unicorn-store-spring}"   # override to build from another copy (reset-app.sh --prebuild)
SKILL_REFS="${REPO_ROOT}/apps/perf-sensor/skills/java-on-eks-optimization/references"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/unicorn-prebuild.XXXXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

# ARG values for the generic Dockerfiles (see EXTRA_BUILD_ARGS in scripts/build.sh).
export JAR_FILE="store-spring-1.0.0-exec.jar"
export MAIN_CLASS="com.unicorn.store.StoreApplication"
export JAVA_HEAP_OPTS="-Xmx480m -Xms320m"   # 640Mi limit x 0.75 / 0.50 (sizing-policy.yaml cracHeap)
export JAVA_CPU_OPTS="-XX:ActiveProcessorCount=1"   # ceil(limits.cpu) = 1

[ -d "${APP_SRC}" ] || { log_error "App dir not found: ${APP_SRC} (run Phase 3 first)"; exit 1; }
[ -x "${APP_SRC}/scripts/build.sh" ] || { log_error "scripts/build.sh missing in ${APP_SRC}"; exit 1; }
[ -f "${SKILL_REFS}/Dockerfile.crac" ] && [ -f "${SKILL_REFS}/Dockerfile.aot" ] \
    || { log_error "Skill Dockerfiles not found in ${SKILL_REFS}"; exit 1; }

log_info "Copying app to ${BUILD_DIR} for the prebuild..."
cp -r "${APP_SRC}/." "${BUILD_DIR}/"
rm -rf "${BUILD_DIR}/.git" "${BUILD_DIR}/target"

# --- CRaC: skill Dockerfile + Resource hook swapped in -------------------------
CRAC_LOG="${WORKSHOP_LOG_DIR}/prebuild-crac.log"
log_info "Prebuilding unicorn-store-spring:crac (full log: ${CRAC_LOG})..."
cp "${SKILL_REFS}/Dockerfile.crac" "${BUILD_DIR}/Dockerfile.crac"
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
( cd "${BUILD_DIR}" && EXTRA_BUILD_ARGS="JAR_FILE JAVA_HEAP_OPTS JAVA_CPU_OPTS" ./scripts/build.sh crac Dockerfile.crac ) >"${CRAC_LOG}" 2>&1 \
    && log_success "unicorn-store-spring:crac pushed" \
    || { log_error "CRaC prebuild failed — last 40 lines of ${CRAC_LOG}:"; tail -n 40 "${CRAC_LOG}"; exit 1; }

# --- AOT: skill Dockerfile on the unmodified source ---------------------------
AOT_LOG="${WORKSHOP_LOG_DIR}/prebuild-aot.log"
log_info "Prebuilding unicorn-store-spring:aot (full log: ${AOT_LOG})..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -r "${APP_SRC}/." "${BUILD_DIR}/"
rm -rf "${BUILD_DIR}/.git" "${BUILD_DIR}/target"
cp "${SKILL_REFS}/Dockerfile.aot" "${BUILD_DIR}/Dockerfile.aot"
( cd "${BUILD_DIR}" && EXTRA_BUILD_ARGS="JAR_FILE MAIN_CLASS" ./scripts/build.sh aot Dockerfile.aot ) >"${AOT_LOG}" 2>&1 \
    && log_success "unicorn-store-spring:aot pushed" \
    || { log_error "AOT prebuild failed — last 40 lines of ${AOT_LOG}:"; tail -n 40 "${AOT_LOG}"; exit 1; }

log_success "Prebuilt images ready: unicorn-store-spring:{crac,aot}"
