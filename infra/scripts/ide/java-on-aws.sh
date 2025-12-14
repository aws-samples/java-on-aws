#!/bin/bash

# Java-on-AWS workshop orchestration script
# This script sets up the complete development environment for Java-on-AWS workshops

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-on-AWS workshop setup..."

# Phase 1: Base development tools
log_info "Phase 1: Setting up base development tools..."
if "$SCRIPT_DIR/base.sh"; then
    log_success "Base development tools setup completed"
else
    log_error "Base development tools setup failed"
    exit 1
fi

# Phase 2: EKS cluster configuration
log_info "Phase 2: Configuring EKS cluster..."
if bash "$SCRIPT_DIR/../setup/eks.sh"; then
    log_success "EKS cluster configuration completed"
else
    log_error "EKS cluster configuration failed"
    exit 1
fi

log_success "Java-on-AWS workshop setup completed successfully!"