#!/bin/bash
# =============================================================================
# java-on-amazon-eks — workshop post-deploy (runs on the IDE as ec2-user, see
# ide/bootstrap.sh; base tools come from ide/tools.sh; /etc/profile.d/workshop.sh
# provides ACCOUNT_ID, AWS_REGION, PREFIX).
#
# Stages, ordered by dependency. Everything that needs no cluster (images, the
# participant's repo, Claude Code wiring) runs in ONE background job while the EKS
# cluster is still being created, which is the longest wait of the bootstrap.
#
#   A  background   app-prepare (repo + :latest), prebuild fallbacks, profiler image,
#                   sensor image, claude-code.sh, prompt
#   B  cluster      eks.sh (waits for ACTIVE), nodepool-pin, metrics-server
#   C  monitoring   Prometheus, Pyroscope, Grafana (shared setup/monitoring.sh)
#      --- wait for A ---
#   D  app          app-deploy (namespace, Pod Identity, manifests)      } in
#   E  platform     perf-profiler install, startup-cpu-boost, perf-sensor } parallel
#   F  verify       ALB answers, sensor measures, Claude wiring present
#
# Each stage script is idempotent and runnable on its own from the IDE.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
DEPLOY="$SCRIPT_DIR/../deploy/java-on-amazon-eks"
SETUP="$SCRIPT_DIR/../setup"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
A_LOG="${WORKSHOP_LOG_DIR}/stage-a.log"
D_LOG="${WORKSHOP_LOG_DIR}/stage-d.log"
E_LOG="${WORKSHOP_LOG_DIR}/stage-e.log"

T0=$SECONDS
stamp() { printf '[%3d min] ' $(( (SECONDS - T0) / 60 )); }
stage() { log_info "$(stamp)Stage $1"; }
# run <label> <script...>: fatal on failure.
run() { local label="$1"; shift; if bash "$@"; then log_success "$(stamp)$label"; else log_error "$(stamp)$label FAILED"; exit 1; fi; }
# try <label> <script...>: warn on failure.
try() { local label="$1"; shift; if bash "$@"; then log_success "$(stamp)$label"; else log_warning "$(stamp)$label failed (non-fatal)"; fi; }

log_info "Starting java-on-amazon-eks post-deploy..."

# --- A: everything without a cluster, in the background --------------------------------
stage "A (background): repo + images + Claude Code"
(
  set -e
  bash "$DEPLOY/app-prepare.sh"
  # Fallback tags from the SHARED source (it still carries the CRaC hook; the participant
  # copy was de-spoiled by app-prepare).
  APP_SRC="$REPO_ROOT/apps/unicorn-store-spring" bash "$DEPLOY/prebuild-images.sh"
  bash "$DEPLOY/perf-profiler.sh" build
  bash "$DEPLOY/perf-sensor.sh" build
  bash "$DEPLOY/claude-code.sh"
  # Prompt: drop vcs, kubecontext and aws segments (three terminals, less noise).
  P10K="$HOME/.p10k.zsh"
  if [ -f "$P10K" ]; then
    sed -i "s/POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs newline prompt_char)/POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir newline prompt_char)/" "$P10K"
    sed -i "s/POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs kubecontext aws newline)/POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs newline)/" "$P10K"
  fi
) >"$A_LOG" 2>&1 &
A_PID=$!

# --- B: cluster ------------------------------------------------------------------------
stage "B: EKS cluster"
run "EKS cluster configured"        "$SETUP/eks.sh"
try "NodePool pinned to m6a"        "$DEPLOY/nodepool-pin.sh"
try "metrics-server installed"      "$DEPLOY/metrics-server.sh"

# --- C: monitoring ---------------------------------------------------------------------
stage "C: monitoring (Prometheus, Pyroscope, Grafana)"
run "Monitoring stack deployed"     "$SETUP/monitoring.sh"

# --- wait for A -------------------------------------------------------------------------
stage "A: waiting for the background job"
if wait "$A_PID"; then
  cat "$A_LOG"
  log_success "$(stamp)Stage A done (repo, :latest, prebuilt tags, profiler + sensor images, Claude Code)"
else
  cat "$A_LOG"
  log_error "$(stamp)Stage A FAILED (see above)"
  exit 1
fi

# --- D + E in parallel -----------------------------------------------------------------
stage "D: app deploy  |  E: profiler, boost, sensor"
bash "$DEPLOY/app-deploy.sh" >"$D_LOG" 2>&1 &
D_PID=$!
(
  set -e
  bash "$DEPLOY/perf-profiler.sh" install
  bash "$DEPLOY/startup-cpu-boost.sh" || echo "⚠️  Startup CPU Boost install failed (manual in-place resize still works)"
  bash "$DEPLOY/perf-sensor.sh" install
) >"$E_LOG" 2>&1 &
E_PID=$!

D_RC=0; wait "$D_PID" || D_RC=$?
E_RC=0; wait "$E_PID" || E_RC=$?
cat "$D_LOG"; cat "$E_LOG"
[ "$D_RC" -eq 0 ] && log_success "$(stamp)Stage D done (app deployed)" || { log_error "$(stamp)Stage D FAILED"; exit 1; }
[ "$E_RC" -eq 0 ] && log_success "$(stamp)Stage E done (profiler, boost, sensor)" || { log_error "$(stamp)Stage E FAILED"; exit 1; }

# --- F: verify --------------------------------------------------------------------------
stage "F: verify"
run "Environment verified"          "$DEPLOY/verify.sh"

log_success "$(stamp)java-on-amazon-eks post-deploy completed"

# Emit for bootstrap summary
echo "✅ Success: Java-on-Amazon-EKS workshop template"
