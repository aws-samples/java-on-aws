#!/bin/bash
# =============================================================================
# ai-agent.sh — configure the AI agents on the IDE for this workshop: Kiro CLI and Claude
# Code get the same skills, the same two MCP servers (perf-sensor and the EKS MCP Server)
# and the same permissions. No cluster needed. Idempotent.
#
# ~/environment holds only skills/, which participants can open. Each tool's own
# configuration lives in the home directory:
#   1. Shared: the two skills copied to ~/environment/skills/.
#   2. Kiro CLI: the agent ~/.kiro/agents/workshop.json (skills, MCP servers, permissions,
#      model), the default agent, effort and harness in ~/.kiro/settings/cli.json, and the
#      trust entry for ~/environment with the approve-for-me policy in
#      ~/.kiro/workspace-roots/<hash>/permissions.yaml.
#   3. Claude Code: ~/.claude/skills/<name> symlinks to ~/environment/skills/<name>, the
#      MCP servers in ~/.claude.json (user scope) and the permissions in
#      ~/.claude/settings.json.
#
# Permissions, the same for both agents: every perf-sensor tool, the EKS MCP read tools by
# name, file reads and edits run without a prompt. Not available: the shell, subagents and
# the EKS MCP write tools. Claude Code also denies edits to .git/**; Kiro always asks for
# them. Everything else is settled by each tool's classifier (Claude Code auto mode, Kiro
# approve-for-me) or asks.
#
# EKS MCP Server: the awslabs eks-mcp-server over local stdio, pinned to a version,
# WITHOUT --allow-write (the server refuses mutations). --allow-sensitive-data-access is
# needed for get_pod_logs and get_k8s_events. Auth uses the IDE role. uv/uvx and the
# package are installed and prewarmed by ide/tools.sh (install_uv); Kiro CLI and Claude
# Code by ide/tools.sh as well.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh
SKILLS_SRC="${REPO_ROOT}/apps/perf-sensor/skills"
ENV_DIR="${ENVIRONMENT_DIR:-${HOME}/environment}"
SKILLS_DIR="${ENV_DIR}/skills"
REGION="${AWS_REGION:?AWS_REGION is not set (/etc/profile.d/workshop.sh)}"
EKS_MCP_VERSION="${EKS_MCP_VERSION:-0.2.1}"   # pinned; bump deliberately (ide/tools.sh prewarms the same version)
KIRO_AGENT="workshop"
KIRO_MODEL="claude-sonnet-5.5"
KIRO_EFFORT="medium"
SKILLS="java-on-eks-optimization java-on-eks-checklist"
SENSOR_URL="http://localhost:8090/mcp"
EKS_READ_TOOLS="list_k8s_resources get_pod_logs get_k8s_events get_eks_insights get_eks_metrics_guidance
get_cloudwatch_logs get_cloudwatch_metrics search_eks_troubleshoot_guide list_api_versions"
EKS_WRITE_TOOLS="apply_yaml manage_k8s_resource manage_eks_stacks add_inline_policy generate_app_manifest"
export ENV_DIR SKILLS_DIR REGION EKS_MCP_VERSION KIRO_AGENT KIRO_MODEL KIRO_EFFORT SENSOR_URL EKS_READ_TOOLS EKS_WRITE_TOOLS

# 1. Skills -> ~/environment/skills/
mkdir -p "${SKILLS_DIR}"
for skill in ${SKILLS}; do
  rm -rf "${SKILLS_DIR:?}/${skill}"
  cp -R "${SKILLS_SRC}/${skill}" "${SKILLS_DIR}/${skill}"
  echo "installed skill: ${SKILLS_DIR}/${skill}"
done

# Workspace files of the earlier Claude-only setup (claude-code.sh), on an IDE that had it.
rm -rf "${ENV_DIR}/.claude" "${ENV_DIR}/.mcp.json"

# 2 + 3. Kiro CLI and Claude Code configuration.
python3 - <<'PY'
import hashlib, json, os

env = os.environ
home = os.path.expanduser("~")
env_dir, skills_dir = env["ENV_DIR"], env["SKILLS_DIR"]
read_tools = env["EKS_READ_TOOLS"].split()
write_tools = env["EKS_WRITE_TOOLS"].split()


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"wrote {path}")


eks_mcp = {
    "command": "uvx",
    "args": [f"awslabs.eks-mcp-server@{env['EKS_MCP_VERSION']}", "--allow-sensitive-data-access"],
    "env": {"AWS_REGION": env["REGION"], "FASTMCP_LOG_LEVEL": "ERROR"},
}

# --- 2. Kiro CLI ---------------------------------------------------------------------
kiro = os.path.join(home, ".kiro")
save(os.path.join(kiro, "agents", f"{env['KIRO_AGENT']}.json"), {
    "name": env["KIRO_AGENT"],
    "description": "Java on Amazon EKS workshop agent: perf-sensor, EKS MCP Server (read-only) and the workshop skills",
    "model": env["KIRO_MODEL"],
    "mcpServers": {"perf-sensor": {"url": env["SENSOR_URL"]}, "eks-mcp": eks_mcp},
    "tools": ["*"],
    "excludedTools": ["shell", "subagent", "invoke_sub_agent"] + [f"@eks-mcp/{t}" for t in write_tools],
    "resources": [f"skill://{skills_dir}/*/SKILL.md"],
    "permissions": {"rules": [
        {"capability": "mcp", "match": ["perf-sensor/*"] + [f"eks-mcp/{t}" for t in read_tools], "effect": "allow"},
        {"capability": "fs_read", "effect": "allow"},
        {"capability": "fs_write", "match": [f"{env_dir}/**"], "effect": "allow"},
    ]},
})

cli_path = os.path.join(kiro, "settings", "cli.json")
cli = load(cli_path)
cli["chat.defaultAgent"] = env["KIRO_AGENT"]
cli["chat.agentEngine"] = "v3"
cli["app.disableAutoupdates"] = True
cli.setdefault("chat.modelDefaults", {}).setdefault(env["KIRO_MODEL"], {}) \
   .setdefault("output_config", {})["effort"] = env["KIRO_EFFORT"]
save(cli_path, cli)

# Trust for ~/environment, so the first interactive launch loads the agent without the
# "Trust this workspace?" screen. The folder key is the first 16 hex characters of the
# sha256 of the absolute path.
root = os.path.realpath(env_dir)
trust_path = os.path.join(kiro, "workspace-roots", hashlib.sha256(root.encode()).hexdigest()[:16], "permissions.yaml")
os.makedirs(os.path.dirname(trust_path), exist_ok=True)
with open(trust_path, "w") as f:
    f.write("rules: []\nworkspaceTrusted: true\npolicies:\n  - approve-for-me\n")
print(f"wrote {trust_path} (trust for {root})")

# --- 3. Claude Code --------------------------------------------------------------------
claude_skills = os.path.join(home, ".claude", "skills")
os.makedirs(claude_skills, exist_ok=True)
for name in sorted(os.listdir(skills_dir)):
    link = os.path.join(claude_skills, name)
    if os.path.islink(link) or os.path.exists(link):
        if os.path.isdir(link) and not os.path.islink(link):
            raise SystemExit(f"{link} is a directory, not the workshop symlink")
        os.remove(link)
    os.symlink(os.path.join(skills_dir, name), link)
    print(f"linked {link} -> {os.path.join(skills_dir, name)}")

claude_json_path = os.path.join(home, ".claude.json")
claude_json = load(claude_json_path)
claude_json.setdefault("mcpServers", {}).update({
    "perf-sensor": {"type": "streamable-http", "url": env["SENSOR_URL"]},
    "eks-mcp": eks_mcp,
})
save(claude_json_path, claude_json)

settings_path = os.path.join(home, ".claude", "settings.json")
settings = load(settings_path)
perms = settings.setdefault("permissions", {})
allow = perms.get("allow", [])
for rule in ["mcp__perf-sensor"] + [f"mcp__eks-mcp__{t}" for t in read_tools] + ["Read", "Grep", "Glob", "Edit", "Write"]:
    if rule not in allow:
        allow.append(rule)
perms["allow"] = allow
deny = perms.get("deny", [])
for rule in ["Bash", "Agent", "Edit(**/.git/**)"] + [f"mcp__eks-mcp__{t}" for t in write_tools]:
    if rule not in deny:
        deny.append(rule)
perms["deny"] = deny
save(settings_path, settings)
PY

echo
echo "Next:"
echo "  # the sensor is on localhost:8090 (systemd perf-sensor-port-forward, from perf-sensor.sh install)"
echo "  cd ${ENV_DIR} && kiro-cli chat   # or: claude"
