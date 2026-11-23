#!/bin/bash
# =============================================================================
# kiro-cli.sh — configure Kiro CLI on the IDE for this workshop: the skills, the two MCP
# servers (perf-sensor + EKS MCP Server), the permissions and the model, so Kiro CLI
# started from ~/environment finds them. Everything is written to the home directory.
# Run after skills.sh. No cluster needed. Idempotent.
#
#   - Agent ~/.kiro/agents/workshop.json: the skills in ~/environment/skills (skills.sh),
#     the app guide ~/environment/unicorn-store-spring/CLAUDE.md, the MCP servers
#     perf-sensor and eks-mcp, the permissions and the model.
#   - ~/.kiro/settings/cli.json: default agent, effort, V3 harness, no auto-updates.
#   - ~/.kiro/workspace-roots/<hash>/permissions.yaml: trust for ~/environment and the
#     approve-for-me policy.
#
# Permissions: every perf-sensor tool, the EKS MCP read tools by name, file reads, edits
# in ~/environment and loading the skills run without a prompt. Not available: the shell,
# subagents and the EKS MCP write tools. Edits to ~/environment/skills/**,
# ~/environment/.claude/** and ~/environment/.mcp.json are denied; Kiro always asks for
# .git/**. Everything else goes to approve-for-me or asks.
# =============================================================================
set -euo pipefail

[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh
ENV_DIR="${ENVIRONMENT_DIR:-${HOME}/environment}"
REGION="${AWS_REGION:?AWS_REGION is not set (/etc/profile.d/workshop.sh)}"
EKS_MCP_VERSION="${EKS_MCP_VERSION:-0.2.1}"   # pinned; ide/tools.sh prewarms the same version
KIRO_AGENT="workshop"
KIRO_MODEL="claude-sonnet-5.5"
KIRO_EFFORT="medium"
EKS_READ_TOOLS="list_k8s_resources get_pod_logs get_k8s_events get_eks_insights get_eks_metrics_guidance
get_cloudwatch_logs get_cloudwatch_metrics search_eks_troubleshoot_guide list_api_versions"
EKS_WRITE_TOOLS="apply_yaml manage_k8s_resource manage_eks_stacks add_inline_policy generate_app_manifest"
for skill in java-on-eks-optimization java-on-eks-checklist; do
  [ -f "${ENV_DIR}/skills/${skill}/SKILL.md" ] || { echo "skill ${skill} missing in ${ENV_DIR}/skills: run skills.sh first" >&2; exit 1; }
done
export ENV_DIR REGION EKS_MCP_VERSION KIRO_AGENT KIRO_MODEL KIRO_EFFORT EKS_READ_TOOLS EKS_WRITE_TOOLS

python3 - <<'PY'
import hashlib, json, os

env = os.environ
home = os.path.expanduser("~")
kiro = os.path.join(home, ".kiro")
env_dir = env["ENV_DIR"]
read_tools = env["EKS_READ_TOOLS"].split()
write_tools = env["EKS_WRITE_TOOLS"].split()


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"wrote {path}")


save(os.path.join(kiro, "agents", f"{env['KIRO_AGENT']}.json"), {
    "name": env["KIRO_AGENT"],
    "description": "Java on Amazon EKS workshop agent: perf-sensor, EKS MCP Server (read-only) and the workshop skills",
    "model": env["KIRO_MODEL"],
    "mcpServers": {
        "perf-sensor": {"url": "http://localhost:8090/mcp"},
        "eks-mcp": {
            "command": "uvx",
            "args": [f"awslabs.eks-mcp-server@{env['EKS_MCP_VERSION']}", "--allow-sensitive-data-access"],
            "env": {"AWS_REGION": env["REGION"], "FASTMCP_LOG_LEVEL": "ERROR"},
        },
    },
    "tools": ["*"],
    "excludedTools": ["shell", "subagent", "invoke_sub_agent"] + [f"@eks-mcp/{t}" for t in write_tools],
    "resources": [
        f"skill://{env_dir}/skills/*/SKILL.md",
        f"file://{env_dir}/unicorn-store-spring/CLAUDE.md",
    ],
    "permissions": {"rules": [
        {"capability": "mcp", "match": ["perf-sensor/*"] + [f"eks-mcp/{t}" for t in read_tools], "effect": "allow"},
        {"capability": "fs_read", "effect": "allow"},
        {"capability": "fs_write", "match": [f"{env_dir}/**"], "effect": "allow"},
        {"capability": "fs_write", "match": [f"{env_dir}/skills/**", f"{env_dir}/.claude/**", f"{env_dir}/.mcp.json"],
         "effect": "deny"},
        {"capability": "skill", "effect": "allow"},
    ]},
})

cli_path = os.path.join(kiro, "settings", "cli.json")
try:
    with open(cli_path) as f:
        cli = json.load(f)
except (OSError, ValueError):
    cli = {}
cli["chat.defaultAgent"] = env["KIRO_AGENT"]
cli["chat.agentEngine"] = "v3"
cli["app.disableAutoupdates"] = True
cli.setdefault("chat.modelDefaults", {}).setdefault(env["KIRO_MODEL"], {}) \
   .setdefault("output_config", {})["effort"] = env["KIRO_EFFORT"]
save(cli_path, cli)

# Folder key: the first 16 hex characters of the sha256 of the absolute path.
root = os.path.realpath(env_dir)
trust_path = os.path.join(kiro, "workspace-roots", hashlib.sha256(root.encode()).hexdigest()[:16], "permissions.yaml")
os.makedirs(os.path.dirname(trust_path), exist_ok=True)
with open(trust_path, "w") as f:
    f.write("rules: []\nworkspaceTrusted: true\npolicies:\n  - approve-for-me\n")
print(f"wrote {trust_path} (trust for {root})")
PY

echo
echo "Next:"
echo "  cd ${ENV_DIR} && kiro-cli chat"
