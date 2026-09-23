#!/bin/bash
# =============================================================================
# claude-code.sh — configure Claude Code on the IDE for this workshop: the skill pack,
# the workspace MCP config (perf-sensor + EKS MCP Server) and the project permissions,
# so Claude Code started from ~/environment finds all three. No cluster needed.
#
# Copies the two skills to ~/environment/.claude/skills/, writes ~/environment/.mcp.json
# (perf-sensor over streamable-http on the port-forward; eks-mcp read-only), writes the
# project permissions, and prints the port-forward command. Idempotent.
#
# EKS MCP Server: the awslabs eks-mcp-server over local stdio, pinned to a version,
# WITHOUT --allow-write (the server refuses mutations). Its tool list still shows the
# write tools (apply_yaml, manage_k8s_resource, ...), so the permissions below allow
# only the read tools by name; anything else prompts.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
SKILLS_SRC="${REPO_ROOT}/apps/perf-sensor/skills"
ENV_DIR="${ENVIRONMENT_DIR:-${HOME}/environment}"
SKILLS_DST="${ENV_DIR}/.claude/skills"
REGION="${AWS_REGION:-us-east-1}"
NS="monitoring"
EKS_MCP_VERSION="${EKS_MCP_VERSION:-0.2.1}"   # pinned; bump deliberately (ide/tools.sh prewarms the same version)

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
        "awslabs.eks-mcp-server@${EKS_MCP_VERSION}",
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

# Auto-approve THIS workshop's two .mcp.json servers so the first `claude` in ~/environment
# doesn't show the "new MCP servers found — Enable" prompt. Project-scoped (not global): only
# perf-sensor + eks-mcp, only for this workspace. Relies on folder trust pre-accepted by
# ide/tools.sh. Merge so we don't clobber any existing project settings.
#
# permissions.allow: the read-only sensor (every perf-sensor tool), the eks-mcp READ tools by
# name, file reads, and edits — so the investigate -> explain -> apply loop runs without
# prompts. permissions.deny closes the two ways the agent could widen its own scope: Bash
# (the participant rolls out; the load runs in its own terminal), and edits to the Claude
# configuration itself (.claude/**, .mcp.json) or to .git/**. Everything not listed prompts.
python3 - "${ENV_DIR}/.claude/settings.json" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
servers = set(data.get("enabledMcpjsonServers", []))
servers.update(["perf-sensor", "eks-mcp"])
data["enabledMcpjsonServers"] = sorted(servers)
perms = data.setdefault("permissions", {})
allow = [r for r in perms.get("allow", []) if r != "mcp__eks-mcp"]   # replace the blanket eks-mcp grant
for rule in ["mcp__perf-sensor",
             "mcp__eks-mcp__list_k8s_resources", "mcp__eks-mcp__get_pod_logs", "mcp__eks-mcp__get_k8s_events",
             "mcp__eks-mcp__get_eks_insights", "mcp__eks-mcp__get_eks_metrics_guidance",
             "mcp__eks-mcp__get_cloudwatch_logs", "mcp__eks-mcp__get_cloudwatch_metrics",
             "mcp__eks-mcp__search_eks_troubleshoot_guide", "mcp__eks-mcp__list_api_versions",
             "Read", "Grep", "Glob", "Edit", "Write"]:
    if rule not in allow:
        allow.append(rule)
perms["allow"] = allow
deny = list(perms.get("deny", []))
for rule in ["Bash",
             "Edit(.claude/**)", "Write(.claude/**)", "Edit(.mcp.json)", "Write(.mcp.json)",
             "Edit(**/.git/**)", "Write(**/.git/**)",
             "mcp__eks-mcp__apply_yaml", "mcp__eks-mcp__manage_k8s_resource", "mcp__eks-mcp__manage_eks_stacks",
             "mcp__eks-mcp__add_inline_policy", "mcp__eks-mcp__generate_app_manifest"]:
    if rule not in deny:
        deny.append(rule)
perms["deny"] = deny
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
echo "wrote ${ENV_DIR}/.claude/settings.json (MCP servers enabled; allow: sensor, eks-mcp read tools, read, edit; deny: Bash, config edits, eks-mcp write tools)"

# No workspace CLAUDE.md: the app repo documents itself (unicorn-store-spring/CLAUDE.md).
# --allow-sensitive-data-access is required for get_pod_logs / get_k8s_events (read-only;
# --allow-write is NOT passed, so the server refuses mutations even if a write tool is
# called). Auth uses the IDE role (default iam mode). uv/uvx and the eks-mcp package are
# installed and prewarmed by ide/tools.sh (install_uv) during base bootstrap.

echo
echo "Next:"
echo "  # run the port-forward in a SEPARATE terminal (it is long-lived and would block the Claude session):"
echo "  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080"
echo "  # then, in your working terminal:"
echo "  cd ${ENV_DIR} && claude   # skills + .mcp.json are picked up from here"
