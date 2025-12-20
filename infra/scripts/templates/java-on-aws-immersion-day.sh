#!/bin/bash

# Java-on-AWS-Immersion-Day workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap
# This script sets up workshop-specific infrastructure (EKS, monitoring, analysis)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-on-AWS-Immersion-Day workshop post-deploy setup..."

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

# Phase 3: Analysis (Thread dump + Profiling)
log_info "Phase 3: Setting up analysis (thread dump + profiling)..."
if bash "$SCRIPT_DIR/../setup/analysis.sh"; then
    log_success "Analysis setup completed"
else
    log_error "Analysis setup failed"
    exit 1
fi

# Phase 4: Unicorn Store Spring (build and push to ECR)
log_info "Phase 4: Building and pushing Unicorn Store Spring..."
if bash "$SCRIPT_DIR/../setup/unicorn-store-spring.sh"; then
    log_success "Unicorn Store Spring setup completed"
else
    log_error "Unicorn Store Spring setup failed"
    exit 1
fi

log_success "Java-on-AWS-Immersion-Day workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-on-AWS-Immersion-Day workshop template"