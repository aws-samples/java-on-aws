#!/bin/bash

# Java-AI-Agents workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap
# This template has base infrastructure + database (no EKS)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-AI-Agents workshop post-deploy setup..."

# Phase 1: Simplify p10k prompt (remove vcs, kubecontext, aws)
log_info "Phase 1: Simplifying p10k prompt..."
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

log_success "Java-AI-Agents workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-AI-Agents workshop template"
