#!/bin/bash

# Java-Spring-AI-Agents workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap
# This script sets up workshop-specific infrastructure (EKS)
# Note: ECS Express services with placeholder images are created by CloudFormation

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-Spring-AI-Agents workshop post-deploy setup..."

# Phase 1: EKS cluster configuration
log_info "Phase 1: Configuring EKS cluster..."
if bash "$SCRIPT_DIR/../setup/eks.sh"; then
    log_success "EKS cluster configuration completed"
else
    log_error "EKS cluster configuration failed"
    exit 1
fi

log_success "Java-Spring-AI-Agents workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-Spring-AI-Agents workshop template"
