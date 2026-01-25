#!/bin/bash

# Java-AI-Agents workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap
# This is a minimal template with base infrastructure only

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-AI-Agents workshop post-deploy setup..."

# No additional setup required for base template
# VPC, IDE, CodeBuild, WorkshopBucket, and EcrRegistry are created by CloudFormation

log_success "Java-AI-Agents workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-AI-Agents workshop template"
