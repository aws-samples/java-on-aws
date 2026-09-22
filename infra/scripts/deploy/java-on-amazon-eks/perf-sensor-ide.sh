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

# Auto-approve THIS workshop's two .mcp.json servers so the first `claude` in ~/environment
# doesn't show the "new MCP servers found — Enable" prompt. Project-scoped (not global): only
# perf-sensor + eks-mcp, only for this workspace. Relies on folder trust pre-accepted by
# ide/tools.sh. Merge so we don't clobber any existing project settings.
#
# permissions.allow: pre-approve the read-only sensors (mcp__<server> = every tool on that
# server), file reads, and edits so the investigate -> explain -> apply loop runs without
# tool prompts. Bash is allowed for ONE command only: the app's own scripts/load.sh (the fixed
# load run the "under load" facts need — documented in the app's CLAUDE.md). kubectl/build/git
# still prompt — rollout stays a participant action we don't block but don't auto-run.
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
allow = list(perms.get("allow", []))
for rule in ["mcp__perf-sensor", "mcp__eks-mcp", "Read", "Grep", "Glob", "Edit", "Write",
             # every spelling Claude uses for the one allowed command (prefix rules)
             "Bash(~/environment/unicorn-store-spring/scripts/load.sh:*)",
             "Bash(" + os.path.expanduser("~") + "/environment/unicorn-store-spring/scripts/load.sh:*)",
             "Bash(bash ~/environment/unicorn-store-spring/scripts/load.sh:*)",
             "Bash(bash " + os.path.expanduser("~") + "/environment/unicorn-store-spring/scripts/load.sh:*)",
             "Bash(unicorn-store-spring/scripts/load.sh:*)",
             "Bash(bash unicorn-store-spring/scripts/load.sh:*)"]:
    if rule not in allow:
        allow.append(rule)
perms["allow"] = allow
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
echo "wrote ${ENV_DIR}/.claude/settings.json (enabledMcpjsonServers + permissions.allow for sensors, read, edit, load.sh)"

# No workspace CLAUDE.md: the app repo documents itself (unicorn-store-spring/CLAUDE.md,
# incl. scripts/load.sh) and the skills tell Claude to look there. Remove a leftover.
rm -f "${ENV_DIR}/CLAUDE.md"
# --allow-sensitive-data-access is required for get_pod_logs / get_k8s_events (read-only;
# write stays off). Auth uses the IDE role (default iam mode). uv/uvx and the eks-mcp
# package are installed and prewarmed by ide/tools.sh (install_uv) during base bootstrap.

echo
echo "Next:"
echo "  # run the port-forward in a SEPARATE terminal (it is long-lived and would block the Claude session):"
echo "  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080"
echo "  # then, in your working terminal:"
echo "  cd ${ENV_DIR} && claude   # skills + .mcp.json are picked up from here"
