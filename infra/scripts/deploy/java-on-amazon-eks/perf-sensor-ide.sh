#!/bin/bash
# =============================================================================
# perf-sensor (IDE side) — install the skill pack and the workspace MCP config so
# Claude Code (started from ~/environment) can drive the sensors + EKS MCP Server.
#
# Copies the two skills to ~/environment/.claude/skills/, writes ~/environment/.mcp.json
# (perf-sensor over streamable-http on the port-forward; eks-mcp read-only), and
# prints the port-forward command. Idempotent.
#
# EKS MCP Server: this writes the awslabs eks-mcp-server over local stdio in
# READ-ONLY mode (the spec's fallback), which needs no SigV4 signing in Claude
# Code and works with the IDE role's default credentials. If Claude Code on the
# IDE can sign SigV4 to a managed EKS MCP endpoint natively, swap the "eks-mcp"
# block for that endpoint. Record which one you used.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
SKILLS_SRC="${REPO_ROOT}/apps/perf-sensor/skills"
ENV_DIR="${ENVIRONMENT_DIR:-${HOME}/environment}"
SKILLS_DST="${ENV_DIR}/.claude/skills"
REGION="${AWS_REGION:-us-east-1}"
NS="monitoring"

# 1. Skills -> ~/environment/.claude/skills/
mkdir -p "${SKILLS_DST}"
for skill in java-on-eks-optimization java-on-eks-checklist; do
  rm -rf "${SKILLS_DST:?}/${skill}"
  cp -R "${SKILLS_SRC}/${skill}" "${SKILLS_DST}/${skill}"
  echo "installed skill: ${SKILLS_DST}/${skill}"
done

# 2. ~/environment/.mcp.json
cat > "${ENV_DIR}/.mcp.json" <<EOF
{
  "mcpServers": {
    "perf-sensor": {
      "type": "streamable-http",
      "url": "http://localhost:8090/mcp"
    },
    "eks-mcp": {
      "command": "uvx",
      "args": [
        "awslabs.eks-mcp-server@latest",
        "--allow-sensitive-data-access"
      ],
      "env": {
        "AWS_REGION": "${REGION}",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
EOF
echo "wrote ${ENV_DIR}/.mcp.json"
# --allow-sensitive-data-access is required for get_pod_logs / get_k8s_events (read-only;
# write stays off). Auth uses the IDE role (default iam mode). uv/uvx and the eks-mcp
# package are installed and prewarmed by ide/tools.sh (install_uv) during base bootstrap.

echo
echo "Next:"
echo "  # run the port-forward in a SEPARATE terminal (it is long-lived and would block the Claude session):"
echo "  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080"
echo "  # then, in your working terminal:"
echo "  cd ${ENV_DIR} && claude   # skills + .mcp.json are picked up from here"
