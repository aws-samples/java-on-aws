#!/bin/bash

# Java-Spring-AI-Agents workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap
# This template uses base infrastructure (no EKS, no Database)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-Spring-AI-Agents workshop post-deploy setup..."

# No additional infrastructure setup needed - uses base template
log_success "Java-Spring-AI-Agents workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-Spring-AI-Agents workshop template"
