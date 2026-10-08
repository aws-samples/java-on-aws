#!/bin/bash
# =============================================================================
# Phase 3a — prebuild the optimized unicorn-store-spring images (:aot-prebuilt, :crac-prebuilt)
#
# Safety net for the builders' session: a CRaC/AOT build (Maven + training/checkpoint run
# against Aurora) takes 1-3 minutes on the IDE and can fail on a bad day. Participants build
# and push :aot / :crac themselves (that IS the lesson); the prebuilt tags are separate so
# a participant's push never overwrites the fallback. If a build fails, the runbook points
# the Deployment at the -prebuilt tag and the session continues.
#
# Builds from a throwaway copy of the participant's app dir so the workshop starting point
# (~/environment/unicorn-store-spring) stays untouched. Uses the generic Dockerfiles the
# optimization skill hands to participants
# (apps/perf-sensor/skills/java-on-eks-optimization/references/Dockerfile.{crac,aot}), with
# their ARGs filled via build-args — same Dockerfile, same ARG values module 4 expects. The
# CRaC checkpoint bakes GC, heap bounds and the processor count in, so JAVA_HEAP_OPTS is
# derived from the memory limit module 1 lands on (PREBUILD_MEM_LIMIT_MI, 768 on the
# reference run: peak ~490 x 1.4 rounded up to 128) with the sizing-policy.yaml cracHeap
# shares (0.75 / 0.50), and JAVA_CPU_OPTS from the CPU limit (1). Swaps in the CRaC Resource
# hook (UnicornPublisher.crac) for the checkpoint build.
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
# Heap flags baked into the checkpoint: 75 % / 50 % of the memory limit module 1 reaches
# (sizing-policy.yaml cracHeap). One number to change if the reference run moves.
PREBUILD_MEM_LIMIT_MI="${PREBUILD_MEM_LIMIT_MI:-768}"
export JAVA_HEAP_OPTS="-Xmx$((PREBUILD_MEM_LIMIT_MI * 3 / 4))m -Xms$((PREBUILD_MEM_LIMIT_MI / 2))m"
export JAVA_CPU_OPTS="-XX:ActiveProcessorCount=1"   # ceil(limits.cpu) = 1
PREBUILT_SUFFIX="-prebuilt"                          # tags participants never push to
# Warm-up request for the CRaC checkpoint: the app's write path.
export WARMUP_CMD="curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d '{\"name\":\"warmup\",\"age\":\"1\",\"type\":\"warmup\",\"size\":\"s\"}' http://localhost:8080/unicorns"

[ -d "${APP_SRC}" ] || { log_error "App dir not found: ${APP_SRC} (run Phase 3 first)"; exit 1; }
[ -x "${APP_SRC}/scripts/build.sh" ] || { log_error "scripts/build.sh missing in ${APP_SRC}"; exit 1; }
[ -f "${SKILL_REFS}/Dockerfile.crac" ] && [ -f "${SKILL_REFS}/Dockerfile.aot" ] \
    || { log_error "Skill Dockerfiles not found in ${SKILL_REFS}"; exit 1; }

log_info "Copying app to ${BUILD_DIR} for the prebuild..."
cp -r "${APP_SRC}/." "${BUILD_DIR}/"
rm -rf "${BUILD_DIR}/.git" "${BUILD_DIR}/target"

# --- CRaC: skill Dockerfile + Resource hook swapped in -------------------------
CRAC_LOG="${WORKSHOP_LOG_DIR}/prebuild-crac.log"
log_info "Prebuilding unicorn-store-spring:crac${PREBUILT_SUFFIX} (limit ${PREBUILD_MEM_LIMIT_MI}Mi -> ${JAVA_HEAP_OPTS}; full log: ${CRAC_LOG})..."
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
( cd "${BUILD_DIR}" && EXTRA_BUILD_ARGS="JAR_FILE JAVA_HEAP_OPTS JAVA_CPU_OPTS WARMUP_CMD" ./scripts/build.sh "crac${PREBUILT_SUFFIX}" Dockerfile.crac ) >"${CRAC_LOG}" 2>&1 \
    && log_success "unicorn-store-spring:crac${PREBUILT_SUFFIX} pushed" \
    || { log_error "CRaC prebuild failed — last 40 lines of ${CRAC_LOG}:"; tail -n 40 "${CRAC_LOG}"; exit 1; }

# --- AOT: skill Dockerfile on the unmodified source ---------------------------
AOT_LOG="${WORKSHOP_LOG_DIR}/prebuild-aot.log"
log_info "Prebuilding unicorn-store-spring:aot${PREBUILT_SUFFIX} (full log: ${AOT_LOG})..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -r "${APP_SRC}/." "${BUILD_DIR}/"
rm -rf "${BUILD_DIR}/.git" "${BUILD_DIR}/target"
cp "${SKILL_REFS}/Dockerfile.aot" "${BUILD_DIR}/Dockerfile.aot"
( cd "${BUILD_DIR}" && EXTRA_BUILD_ARGS="JAR_FILE MAIN_CLASS" ./scripts/build.sh "aot${PREBUILT_SUFFIX}" Dockerfile.aot ) >"${AOT_LOG}" 2>&1 \
    && log_success "unicorn-store-spring:aot${PREBUILT_SUFFIX} pushed" \
    || { log_error "AOT prebuild failed — last 40 lines of ${AOT_LOG}:"; tail -n 40 "${AOT_LOG}"; exit 1; }

log_success "Prebuilt fallback images ready: unicorn-store-spring:{crac,aot}${PREBUILT_SUFFIX}"
