#!/bin/bash

# agentcore-ai-agents workshop post-deploy script
# Base development tools (Docker, jq, direnv, uv, nvm) are already installed by ide/tools.sh during bootstrap;
# the workshop code is in ~/java-on-aws/apps/agentcore-ai-agents, and the files the content uses are copied to ~/workshop.
# Model note: the workshop uses Claude Sonnet 5.5 (global cross-Region inference); iam/common.json allows the
# AWS Marketplace subscription for it on the IDE and participant roles.

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

# Phase 2: the files the content uses, in ~/workshop (outside the editor's ~/environment; the content never reads
# ~/java-on-aws). The IDE stand-in of the content repository (docs/spikes/ws-test/run-workshop.sh) makes the same copy.
log_info "Phase 2: workshop files in ~/workshop..."
APP_DIR="$HOME/java-on-aws/apps/agentcore-ai-agents"
mkdir -p "$HOME/workshop"
cp -R "$APP_DIR/scripts" "$APP_DIR/ui" "$APP_DIR/samples" "$APP_DIR/receipt-lambda" "$HOME/workshop/"
cp "$HOME/java-on-aws/infra/scripts/cleanup/agentcore-ai-agents.sh" "$HOME/workshop/scripts/cleanup.sh"
for BACKOFFICE in backoffice-java backoffice-python backoffice-ts; do
  mkdir -p "$HOME/workshop/$BACKOFFICE"
  cp -R "$APP_DIR/$BACKOFFICE/app" "$HOME/workshop/$BACKOFFICE/"
done

log_success "agentcore-ai-agents workshop post-deploy setup completed successfully!"

# Emit for bootstrap summary
echo "✅ Success: agentcore-ai-agents workshop template"
