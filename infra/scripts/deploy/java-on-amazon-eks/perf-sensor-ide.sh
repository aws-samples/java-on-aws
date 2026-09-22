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
# tool prompts. Bash is allowed for ONE command only: infra/scripts/test/load.sh (the fixed
# load run the "under load" facts need — see ~/environment/CLAUDE.md). kubectl/build/git still
# prompt — rollout stays a participant action we don't block but don't auto-run.
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
             "Bash(~/java-on-aws/infra/scripts/test/load.sh:*)",
             "Bash(" + os.path.expanduser("~") + "/java-on-aws/infra/scripts/test/load.sh:*)"]:
    if rule not in allow:
        allow.append(rule)
perms["allow"] = allow
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
echo "wrote ${ENV_DIR}/.claude/settings.json (enabledMcpjsonServers + permissions.allow for sensors, read, edit, load.sh)"

# ~/environment/CLAUDE.md: what THIS environment expects from Claude on top of the generic
# skills — how to get traffic for the facts that need it, and that nothing else is run here.
# Workspace-level on purpose: the skills know no workshop, the app repo is a plain app.
cat > "${ENV_DIR}/CLAUDE.md" <<'MD'
# Working in this environment

The Java service under study lives in `unicorn-store-spring/` (a plain Spring Boot app,
deployed to the EKS cluster in namespace `unicorn-store-spring`). Its measurements come from
the `perf-sensor` MCP tools; the skills in `.claude/skills/` say how to read them.

## Load

Some facts exist only while requests are flowing: memory peak, CPU p95, CFS throttling,
blocked request threads, request latency. The sensor never generates traffic. When a
checklist item or a question needs those facts and `window.requestRatePerSec` is below 1,
or `diagnoseBlocking` returns BLOCKED, start the load yourself, then call the tools:

    ~/java-on-aws/infra/scripts/test/load.sh

It sends 50 writes/s for 120 s and returns after 90 s with ~30 s of load still flowing —
measure right after it returns. Do not start it when the rate is already above 1 (a load
run is flowing), and do not run it more than once per question.

## Commands

`load.sh` is the only command to run here. Do not run `kubectl`, `docker`, build scripts or
`git`: rolling out, building and committing are the developer's steps, done after the
changes are reviewed.
MD
echo "wrote ${ENV_DIR}/CLAUDE.md"
# --allow-sensitive-data-access is required for get_pod_logs / get_k8s_events (read-only;
# write stays off). Auth uses the IDE role (default iam mode). uv/uvx and the eks-mcp
# package are installed and prewarmed by ide/tools.sh (install_uv) during base bootstrap.

echo
echo "Next:"
echo "  # run the port-forward in a SEPARATE terminal (it is long-lived and would block the Claude session):"
echo "  kubectl -n ${NS} port-forward svc/perf-sensor 8090:8080"
echo "  # then, in your working terminal:"
echo "  cd ${ENV_DIR} && claude   # skills + .mcp.json are picked up from here"
