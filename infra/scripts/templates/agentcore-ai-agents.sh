#!/bin/bash

# agentcore-ai-agents workshop post-deploy script
# Base development tools (Docker, jq, direnv, uv, nvm) are already installed by ide/tools.sh during bootstrap;
# the workshop code is in ~/java-on-aws/apps/agentcore-ai-agents.
# Model note: the workshop uses Claude Sonnet 4.6; Claude Sonnet 5 / 5.5 need an AWS Marketplace
# subscription per account, which the participant role cannot make (aws-marketplace:Subscribe).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../ide/functions.sh"

log_info "Starting agentcore-ai-agents workshop post-deploy setup..."

# Phase 1: Node.js 22 (the TypeScript apps and the AgentCore CLI are tested with it)
log_info "Phase 1: Node.js 22..."
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
source "$NVM_DIR/nvm.sh"
retry_critical "Node.js 22" "nvm install 22 >/dev/null"
nvm alias default 22 >/dev/null

log_success "agentcore-ai-agents workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: agentcore-ai-agents workshop template"
