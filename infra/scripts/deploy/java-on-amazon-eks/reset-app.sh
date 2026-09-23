#!/bin/bash
# =============================================================================
# reset-app.sh — put a used environment back to the workshop starting point.
#
# For repeated acceptance runs (apps/perf-sensor/ACCEPTANCE.md) on the same env.
# Everything a run changes in the APP is reverted; the platform (monitoring,
# profiler policy, sensor, boost controller, skills) is left as bootstrapped.
#
#   1. ~/environment/unicorn-store-spring: hard reset to the commit
#      "Starting point: containerized + deployed to EKS" (made by app-prepare.sh), untracked files removed
#      (Dockerfile.aot/.crac, startup-cpu-boost.yaml, listener classes ...); then
#      scripts/load.sh, scripts/build.sh and CLAUDE.md are synced from the shared
#      source (apps/unicorn-store-spring) and folded into that commit, so the
#      starting point always carries the current versions.
#   2. StartupCPUBoost CRs in the app namespace deleted (created in module 2;
#      the CR outlives the manifest reset).
#   3. Baseline manifest applied (:latest, 1 vCPU / 2Gi, no sidecar label) and
#      rolled out; image, resources and container list verified.
#   4. ~/environment/baseline.txt removed.
#   5. Claude Code per-run state under ~/.claude removed (projects/ = transcripts
#      `-c` would resume + auto-memory, sessions/, session-env/, shell-snapshots/,
#      backups/, downloads/). KEPT: ~/.claude/settings.json, ~/.claude.json, and the
#      workshop wiring in ~/environment/.claude/ + ~/environment/.mcp.json.
#   6. --prebuild: rebuild the :aot-prebuilt / :crac-prebuilt fallback tags from the
#      SHARED source (~/java-on-aws/apps/unicorn-store-spring, which still carries the
#      CRaC hook). Participant builds push :aot / :crac, so the fallbacks survive a run;
#      pass this only when the shared source changed. Several minutes.
#
# NOT touched: the Aurora rows the load runs inserted (nothing reads them) and the
# Prometheus/Pyroscope history (the sensor scopes to the current pod).
#
# Runs on the IDE instance. Usage: reset-app.sh [--prebuild]
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/../../lib/common.sh" ] && source "${SCRIPT_DIR}/../../lib/common.sh"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh
command -v log_info >/dev/null 2>&1 || {
  log_info()    { echo "ℹ️  $*"; }
  log_success() { echo "✅ $*"; }
  log_warning() { echo "⚠️  $*"; }
  log_error()   { echo "❌ $*" >&2; }
}

APP_NS="unicorn-store-spring"
APP_DIR="${HOME}/environment/unicorn-store-spring"
SHARED_SRC="$(cd "${SCRIPT_DIR}/../../../.." && pwd)/apps/unicorn-store-spring"
START_MSG="Starting point: containerized + deployed to EKS"
PREBUILD=false
[ "${1:-}" = "--prebuild" ] && PREBUILD=true

[ -d "${APP_DIR}/.git" ] || { log_error "No git repo at ${APP_DIR}"; exit 1; }

# 1. App repo back to the starting point.
START_SHA="$(git -C "${APP_DIR}" log --format=%H --grep="${START_MSG}" -n 1)"
[ -n "${START_SHA}" ] || { log_error "Commit '${START_MSG}' not found in ${APP_DIR}"; exit 1; }
log_info "Resetting ${APP_DIR} to ${START_SHA:0:8} ('${START_MSG}')..."
git -C "${APP_DIR}" reset -q --hard "${START_SHA}" \
  && git -C "${APP_DIR}" clean -fdq \
  && log_success "App repo at starting point ($(git -C "${APP_DIR}" status --porcelain | wc -l | tr -d ' ') changes left)" \
  || { log_error "git reset failed"; exit 1; }

# 1b. The starting point must carry the CURRENT shared-source versions of the files the
# workshop ships with the app (they change between runs; the participant copy was taken at
# bootstrap). Sync them and fold them into the starting-point commit, so a later reset
# never brings an old script back.
SYNCED=""
for f in scripts/load.sh scripts/build.sh CLAUDE.md; do
  if [ -f "${SHARED_SRC}/${f}" ] && ! cmp -s "${SHARED_SRC}/${f}" "${APP_DIR}/${f}"; then
    mkdir -p "$(dirname "${APP_DIR}/${f}")"
    cp "${SHARED_SRC}/${f}" "${APP_DIR}/${f}"
    SYNCED="${SYNCED} ${f}"
  fi
done
if [ -n "${SYNCED}" ]; then
  git -C "${APP_DIR}" add -A \
    && git -C "${APP_DIR}" commit -q --amend --no-edit \
    && log_success "Starting point updated from shared source:${SYNCED}" \
    || { log_error "could not fold synced files into the starting-point commit"; exit 1; }
fi

# 2. Module 2's CR outlives the manifest.
kubectl -n "${APP_NS}" delete startupcpuboost --all --ignore-not-found >/dev/null 2>&1 \
  && log_success "StartupCPUBoost CRs removed" \
  || log_warning "could not delete StartupCPUBoost CRs (CRD absent?)"

# 3. Baseline deployment.
MANIFEST="${APP_DIR}/k8s/deployment.yaml"
[ -f "${MANIFEST}" ] || { log_error "Manifest not found: ${MANIFEST}"; exit 1; }
log_info "Applying baseline manifest and waiting for rollout..."
kubectl -n "${APP_NS}" apply -f "${MANIFEST}" >/dev/null \
  && kubectl -n "${APP_NS}" rollout status deploy/unicorn-store-spring --timeout=300s >/dev/null \
  || { log_error "baseline rollout failed"; exit 1; }

# Read the NEW pod: right after rollout status the old one is still Terminating and
# sorts first, so filter on phase=Running and no deletionTimestamp, newest first.
POD="$(kubectl -n "${APP_NS}" get pod -l app=unicorn-store-spring --field-selector=status.phase=Running -o json \
  | jq -r '[.items[] | select(.metadata.deletionTimestamp == null)] | sort_by(.status.startTime) | last | .metadata.name')"
IMAGE="$(kubectl -n "${APP_NS}" get pod "${POD}" -o jsonpath='{.spec.containers[0].image}')"
RES="$(kubectl -n "${APP_NS}" get pod "${POD}" -o jsonpath='{.spec.containers[0].resources}')"
CONTAINERS="$(kubectl -n "${APP_NS}" get pod "${POD}" -o jsonpath='{.spec.containers[*].name}')"
log_info "pod:        ${POD}"
log_info "image:      ${IMAGE}"
log_info "resources:  ${RES}"
log_info "containers: ${CONTAINERS}"
case "${IMAGE}" in *:latest) ;; *) log_warning "image tag is not :latest";; esac
[ "${CONTAINERS}" = "unicorn-store-spring" ] || log_warning "sidecar still present — label reset did not take?"
log_success "Baseline deployed"

# 4. Run artefacts.
rm -f "${HOME}/environment/baseline.txt"

# 5. Claude Code per-run state (keep settings.json and ~/.claude.json).
if [ -d "${HOME}/.claude" ]; then
  rm -rf "${HOME}/.claude/projects" "${HOME}/.claude/sessions" "${HOME}/.claude/session-env" \
         "${HOME}/.claude/shell-snapshots" "${HOME}/.claude/backups" "${HOME}/.claude/downloads"
  log_success "Claude Code sessions/transcripts/memory cleared (settings kept)"
fi

# 6. Optional: restore the prebuilt tags from the shared (not de-spoiled) source.
if ${PREBUILD}; then
  [ -f "${SHARED_SRC}/src/main/java/com/unicorn/store/data/UnicornPublisher.crac" ] \
    || { log_error "Shared source lacks UnicornPublisher.crac: ${SHARED_SRC}"; exit 1; }
  log_info "Rebuilding :aot and :crac from ${SHARED_SRC} (several minutes)..."
  APP_SRC="${SHARED_SRC}" bash "${SCRIPT_DIR}/prebuild-images.sh" \
    && log_success "Prebuilt tags restored" \
    || { log_error "prebuild failed"; exit 1; }
else
  log_info ":aot-prebuilt/:crac-prebuilt fallbacks untouched by the run (pass --prebuild to rebuild them from the shared source)"
fi

log_success "Environment at starting point. Next: ACCEPTANCE.md §2 (claude -p, not -c)."
