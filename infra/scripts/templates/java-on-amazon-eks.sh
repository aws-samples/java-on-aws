#!/bin/bash

# Java-on-Amazon-EKS workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap.
# Runs on the IDE instance as ec2-user (see ide/bootstrap.sh) with the IDE role
# and /etc/profile.d/workshop.sh sourced (ACCOUNT_ID, AWS_REGION, ...).
#
# This script provisions the workshop STARTING POINT only (EKS config, monitoring,
# app prepared + built). The steps that deploy the app and the perf tooling are
# kept commented out below: run them by hand on the IDE to validate, then uncomment
# to wire them into the bootstrap once proven.

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-on-Amazon-EKS workshop post-deploy setup..."

# Phase 1: EKS cluster configuration
log_info "Phase 1: Configuring EKS cluster..."
if bash "$SCRIPT_DIR/../setup/eks.sh"; then
    log_success "EKS cluster configuration completed"
else
    log_error "EKS cluster configuration failed"
    exit 1
fi

# Phase 2: Monitoring stack (Prometheus + Grafana)
log_info "Phase 2: Setting up monitoring stack..."
if bash "$SCRIPT_DIR/../setup/monitoring.sh"; then
    log_success "Monitoring stack setup completed"
else
    log_error "Monitoring stack setup failed"
    exit 1
fi

# Phase 3: Unicorn Store Spring (prepare sources in ~/environment, git init, build)
log_info "Phase 3: Building and pushing Unicorn Store Spring..."
if bash "$SCRIPT_DIR/../setup/unicorn-store-spring.sh"; then
    log_success "Unicorn Store Spring setup completed"
else
    log_error "Unicorn Store Spring setup failed"
    exit 1
fi

# ---------------------------------------------------------------------------
# Workshop tooling — runs as ec2-user with the IDE role, after the starting point.
# ---------------------------------------------------------------------------

# Phase 4: Containerize + deploy the baseline app to EKS.
# Replays the immersion-day containerize (page 50) and deploy-to-EKS (page 120)
# labs; page-only --to 140 stops before ECS (page 140), so ECS is skipped. Leaves
# the Dockerfile + k8s/*.yaml in ~/environment/unicorn-store-spring and the app live.
log_info "Phase 4: Containerize + deploy baseline app to EKS..."
if bash "$SCRIPT_DIR/../ws-test/java-on-aws.sh" --from 50 --to 140; then
    log_success "Baseline app deployed to EKS"
else
    log_error "Baseline app deploy failed"
    exit 1
fi

# Phase 5: Commit the starting point into the participant's local repo.
# (unicorn-store-spring.sh already did `git init` + the initial commit; this
# captures the lab-generated Dockerfile + k8s manifests.)
log_info "Phase 5: Committing workshop starting point..."
( cd ~/environment/unicorn-store-spring \
    && git add -A \
    && git commit -m "Starting point: containerized + deployed to EKS" ) \
    && log_success "Starting point committed" \
    || log_warning "Nothing to commit (starting point already committed)"

# Phase 6: Privilege-free profiler (build/push image, install Kyverno + metrics-server,
# apply the sidecar-injection MutatingPolicy). Pyroscope + Grafana wiring already
# came up in Phase 2 (monitoring.sh); CON405 does NOT run perf-platform.sh.
log_info "Phase 6: Deploying perf-profiler..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/perf-profiler.sh"; then
    log_success "perf-profiler deployed"
else
    log_error "perf-profiler deploy failed"
    exit 1
fi

# Phase 6b: Opt unicorn-store-spring into profiling. The app is deployed (by the
# lab content) BEFORE the inject policy exists, and the participant manifest carries
# no sidecar label — so patch the label onto the pod template here. The patch rolls
# the pods, which pass admission and get the profiler sidecar injected. Done in the
# bootstrap (not in participant content) because the profiler is platform-provided.
# Non-fatal — the sensor still measures (memory/startup/workload) without the sidecar;
# only profileTop/threadDump/heap need it.
log_info "Phase 6b: Opting unicorn-store-spring into profiling (sidecar injection)..."
if kubectl -n unicorn-store-spring patch deploy/unicorn-store-spring --type merge \
     -p '{"spec":{"template":{"metadata":{"labels":{"perf-profile/sidecar":"true"}}}}}' >/dev/null 2>&1 \
   && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=240s >/dev/null 2>&1; then
    log_success "unicorn-store-spring opted into profiling (sidecar injected)"
else
    log_warning "could not opt unicorn-store-spring into profiling (profileTop/threadDump may be empty)"
fi

# Phase 7: perf-sensor — deterministic sensors (MCP + REST). Primary optimization
# path for CON405 (replaces the retired perf-optimizer agent). Fatal: the session
# depends on it.
log_info "Phase 7: Deploying perf-sensor..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/perf-sensor.sh"; then
    log_success "perf-sensor deployed"
else
    log_error "perf-sensor deploy failed"
    exit 1
fi

# Phase 7b: install the skill pack + ~/environment/.mcp.json on the IDE.
log_info "Phase 7b: Installing perf-sensor skills + .mcp.json on the IDE..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/perf-sensor-ide.sh"; then
    log_success "perf-sensor skills + .mcp.json installed"
else
    log_error "perf-sensor-ide setup failed"
    exit 1
fi

# Phase 7c: Prebuild the optimized app images (:crac, :aot) so the session deploys
# them without waiting on a multi-minute CRaC/AOT build.
log_info "Phase 7c: Prebuilding unicorn-store-spring:{crac,aot}..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/prebuild-images.sh"; then
    log_success "Optimized images prebuilt"
else
    log_error "Prebuild of optimized images failed"
    exit 1
fi

# Phase 8: Simplify p10k prompt (remove vcs, kubecontext, aws)
log_info "Phase 8: Simplifying p10k prompt..."
P10K_FILE="$HOME/.p10k.zsh"
if [[ -f "$P10K_FILE" ]]; then
    # Remove vcs from left prompt
    sed -i "s/POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs newline prompt_char)/POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir newline prompt_char)/" "$P10K_FILE"
    # Remove kubecontext and aws from right prompt
    sed -i "s/POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs kubecontext aws newline)/POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs newline)/" "$P10K_FILE"
    log_success "p10k prompt simplified"
else
    log_warning "p10k.zsh not found, skipping prompt customization"
fi

log_success "Java-on-Amazon-EKS workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-on-Amazon-EKS workshop template"
