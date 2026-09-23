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

# Phase 1b: Pin the workshop NodePool to one instance family (m6a) so startup timings
# are comparable across the session. java-on-amazon-eks-specific; setup/eks.sh stays shared.
log_info "Phase 1b: Pinning NodePool to m6a..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/nodepool-pin.sh"; then
    log_success "NodePool pinned"
else
    log_warning "NodePool pin failed (startup numbers may vary with the instance type)"
fi

# Phase 1c: metrics-server, for kubectl top and eks-node-viewer's utilization column.
# java-on-amazon-eks-specific; nothing in the sensor path depends on it.
log_info "Phase 1c: Installing metrics-server..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/metrics-server.sh"; then
    log_success "metrics-server installed"
else
    log_warning "metrics-server install failed (eks-node-viewer shows requests only)"
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

# Phase 3a: Prebuild the fallback app images (:crac-prebuilt, :aot-prebuilt) so a failed
# participant build does not stall the session. MUST run BEFORE Phase 3b:
# the CRaC checkpoint needs org.crac + the UnicornPublisher.crac hook, which de-spoil
# strips out. prebuild-images.sh builds from a throwaway copy, so it leaves the
# participant dir untouched — de-spoil and the clean starting-point commit stay correct.
log_info "Phase 3a: Prebuilding unicorn-store-spring:{crac,aot}-prebuilt fallbacks..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/prebuild-images.sh"; then
    log_success "Optimized images prebuilt"
else
    log_error "Prebuild of optimized images failed"
    exit 1
fi

# Phase 3b: De-spoil the participant's app copy (leaves the shared apps/ source and the
# immersion-day module untouched). The CRaC optimization (Q4) should be DISCOVERED, so
# strip the pre-baked answer from ~/environment: remove the org.crac dependency from
# pom.xml (the optimization skill re-adds it) and delete the finished CRaC reference
# implementation (UnicornPublisher.crac). Non-fatal.
log_info "Phase 3b: De-spoiling app copy (remove org.crac dep + CRaC crib)..."
APP_SRC="$HOME/environment/unicorn-store-spring"
if [ -d "$APP_SRC" ]; then
    # Remove the whole <dependencies> block that carries org.crac (only crac lives there).
    perl -0777 -i -pe 's{\s*<dependencies>\s*<dependency>\s*<groupId>org\.crac</groupId>.*?</dependencies>}{}s' \
        "$APP_SRC/pom.xml" 2>/dev/null || true
    find "$APP_SRC/src" -name '*.crac' -delete 2>/dev/null || true
    log_success "App copy de-spoiled (org.crac dep + *.crac removed)"
else
    log_warning "app copy not found at $APP_SRC — skipped de-spoil"
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

# Phase 4b: Clean the deployed manifest's probes and make the app scrapeable. The
# lab-generated manifest carries redundant probe initialDelaySeconds (startup:20 — the
# failureThreshold budget is the lever; readiness:10 never fires while a startupProbe
# exists); drop them so the starting manifest is clean. Add the prometheus.io scrape
# annotations: monitoring.sh's Prometheus discovers pods by annotation, and the sensor's
# startup/latency/request-rate facts come from the app's /actuator/prometheus.
# Resource requests/limits (1 vCPU / 2Gi, Guaranteed) are KEPT: the baseline must be a
# bounded JVM — without a CPU limit the pod boots on the whole node (~6 s instead of
# ~13 s) and the startup story is wrong.
# Must run AFTER Phase 4 (which regenerates the manifest) and BEFORE the Phase 5 commit,
# so the participant's starting-point commit already carries the cleaned manifest.
# Non-fatal.
log_info "Phase 4b: Cleaning deployed manifest (probe delays, scrape annotations)..."
DEPLOY_MANIFEST="$HOME/environment/unicorn-store-spring/k8s/deployment.yaml"
if [ -f "$DEPLOY_MANIFEST" ] \
   && yq -i 'del(.spec.template.spec.containers[].startupProbe.initialDelaySeconds, .spec.template.spec.containers[].readinessProbe.initialDelaySeconds)
             | .spec.template.metadata.annotations."prometheus.io/scrape" = "true"
             | .spec.template.metadata.annotations."prometheus.io/path" = "/actuator/prometheus"
             | .spec.template.metadata.annotations."prometheus.io/port" = "8080"' "$DEPLOY_MANIFEST" \
   && kubectl -n unicorn-store-spring apply -f "$DEPLOY_MANIFEST" >/dev/null 2>&1 \
   && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=240s >/dev/null 2>&1; then
    log_success "Manifest cleaned (probe delays removed, scrape annotations added)"
else
    log_warning "could not clean the deployed manifest"
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

# Phase 6: Privilege-free profiler (build/push image, install Kyverno, apply the
# sidecar-injection MutatingPolicy). Pyroscope + Grafana wiring already came up in
# Phase 2 (monitoring.sh); java-on-amazon-eks does NOT run perf-platform.sh.
log_info "Phase 6: Deploying perf-profiler..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/perf-profiler.sh"; then
    log_success "perf-profiler deployed"
else
    log_error "perf-profiler deploy failed"
    exit 1
fi

# Phase 6b: (disabled) Profiler attach is now the OPENING participant step, not a
# bootstrap pre-injection. The Kyverno sidecar-injection policy is installed in Phase 6;
# the participant opts their workload in by adding the `perf-profile/sidecar: "true"`
# label themselves (content/baseline: yq the label -> apply -> commit), which teaches
# observability-first and keeps the profiler out of the scored checklist (it's tooling,
# not a best practice). Left here (commented) so the mechanism is discoverable; do NOT
# re-enable — pre-attaching hides the opening step and re-adds the profiler as a freebie.
#
# log_info "Phase 6b: Opting unicorn-store-spring into profiling (sidecar injection)..."
# DEPLOY_MANIFEST="$HOME/environment/unicorn-store-spring/k8s/deployment.yaml"
# if [ -f "$DEPLOY_MANIFEST" ] \
#    && yq -i '.spec.template.metadata.labels."perf-profile/sidecar" = "true"' "$DEPLOY_MANIFEST" \
#    && kubectl -n unicorn-store-spring apply -f "$DEPLOY_MANIFEST" >/dev/null 2>&1 \
#    && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=240s >/dev/null 2>&1; then
#     ( cd "$HOME/environment/unicorn-store-spring" \
#         && git add k8s/deployment.yaml \
#         && git commit -m "Opt into profiler sidecar injection (perf-profile/sidecar label)" ) \
#         >/dev/null 2>&1 || true
#     log_success "unicorn-store-spring opted into profiling (sidecar label in manifest, injected)"
# else
#     log_warning "could not opt unicorn-store-spring into profiling (profileTop/threadDump may be empty)"
# fi

# Phase 6c: Kube Startup CPU Boost — cluster-wide controller (platform install) so the
# "start faster without changing the image" answer hands developers a declarative
# StartupCPUBoost CR instead of a manual per-pod resize. Non-fatal: the skill's manual
# in-place-resize path still works if the controller is absent.
log_info "Phase 6c: Installing Kube Startup CPU Boost controller..."
if bash "$SCRIPT_DIR/../deploy/java-on-amazon-eks/startup-cpu-boost.sh"; then
    log_success "Kube Startup CPU Boost installed"
else
    log_warning "Kube Startup CPU Boost install failed (manual in-place-resize still available)"
fi

# Phase 7: perf-sensor — deterministic sensors (MCP + REST). Primary optimization
# path for java-on-amazon-eks. Fatal: the session depends on it.
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
