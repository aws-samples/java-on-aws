#!/bin/bash

# Java-AI-Agents-Advanced workshop post-deploy script
# Base development tools are already installed by ide/tools.sh during bootstrap
# This template has base infrastructure + database (no EKS)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting Java-AI-Agents-Advanced workshop post-deploy setup..."

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

# Phase 2: Run full AI agents deployment
log_info "Phase 2: Running full AI agents deployment (00-deploy-all.sh)..."
DEPLOY_SCRIPT="$HOME/java-on-aws/apps/java-spring-ai-agents/scripts/00-deploy-all.sh"
if [[ -f "$DEPLOY_SCRIPT" ]]; then
    if bash "$DEPLOY_SCRIPT"; then
        log_success "AI agents deployment completed"
    else
        log_error "AI agents deployment failed"
        exit 1
    fi
else
    log_error "Deploy script not found: $DEPLOY_SCRIPT"
    exit 1
fi

log_success "Java-AI-Agents-Advanced workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: Java-AI-Agents-Advanced workshop template"
