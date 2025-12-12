#!/bin/bash

# IDE workshop orchestration script
source "$(dirname "$0")/../lib/common.sh"

log_info "Starting IDE workshop setup..."

# Run base setup
log_info "Running base setup..."
"$(dirname "$0")/../setup/base.sh" || {
    log_error "Base setup failed"
    exit 1
}

# Run IDE-specific setup
log_info "Running IDE-specific setup..."
"$(dirname "$0")/../setup/ide.sh" || {
    log_error "IDE setup failed"
    exit 1
}

log_success "IDE workshop setup completed successfully!"