#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

usage() {
  cat <<'EOF'
Usage: 00-deploy-all.sh [--target all|eks|ecs|lambda|agentcore] [--force] [--rotate-passwords]

Runs shared setup, prerequisite validation, MCP deployment, Cognito, the selected
AI-agent target or all targets, observability, and hard-failing behavioral tests.
With no --target argument, all targets are deployed and tested. Cleanup is never run.
EOF
}

TARGET="all"
TARGET_SET=false
FORCE=false
ROTATE=false
while (($#)); do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      [[ "${TARGET_SET}" == false ]] || die "--target may be specified only once"
      TARGET="$2"
      TARGET_SET=true
      shift 2
      ;;
    --force) FORCE=true; shift ;;
    --rotate-passwords) ROTATE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown argument: $1" ;;
  esac
done
[[ "${TARGET}" =~ ^(all|eks|ecs|lambda|agentcore)$ ]] || {
  usage >&2
  die "--target must be all, eks, ecs, lambda, or agentcore"
}
print_prerequisites "all shared-stage tools plus the selected deployment target tools"

setup_args=()
security_args=()
${FORCE} && setup_args+=(--force)
${ROTATE} && security_args+=(--rotate-passwords)

"${SCRIPT_DIR}/01-setup.sh" "${setup_args[@]}"
"${SCRIPT_DIR}/02-memory.sh"
"${SCRIPT_DIR}/03-knowledge.sh"
"${SCRIPT_DIR}/04-mcp-server.sh"
"${SCRIPT_DIR}/05-security.sh" "${security_args[@]}"

if [[ "${TARGET}" == all ]]; then
  DEPLOYED_TARGETS=(eks ecs lambda agentcore)
  "${SCRIPT_DIR}/10-deploy-eks.sh"
  "${SCRIPT_DIR}/11-deploy-ecs.sh"
  "${SCRIPT_DIR}/12-deploy-lambda.sh"
  "${SCRIPT_DIR}/13-deploy-agentcore.sh"
else
  DEPLOYED_TARGETS=("${TARGET}")
  case "${TARGET}" in
    eks) "${SCRIPT_DIR}/10-deploy-eks.sh" ;;
    ecs) "${SCRIPT_DIR}/11-deploy-ecs.sh" ;;
    lambda) "${SCRIPT_DIR}/12-deploy-lambda.sh" ;;
    agentcore) "${SCRIPT_DIR}/13-deploy-agentcore.sh" ;;
  esac
fi

"${SCRIPT_DIR}/20-observability.sh"
for deployed_target in "${DEPLOYED_TARGETS[@]}"; do
  "${SCRIPT_DIR}/30-test.sh" --target "${deployed_target}"
done
log "Deployment and tests completed for target selection: ${TARGET}"
