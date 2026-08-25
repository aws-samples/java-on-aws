#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

usage() {
  cat <<'EOF'
Usage: 00-deploy-all.sh --target eks|ecs|lambda|agentcore [--force] [--rotate-passwords]

Runs shared setup, prerequisite validation, MCP deployment, Cognito, exactly one
AI-agent target, observability, and the hard-failing test suite. Cleanup is never run.
EOF
}

TARGET=""
TARGET_COUNT=0
FORCE=false
ROTATE=false
while (($#)); do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      TARGET="$2"
      ((TARGET_COUNT += 1))
      shift 2
      ;;
    --force) FORCE=true; shift ;;
    --rotate-passwords) ROTATE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown argument: $1" ;;
  esac
done
[[ "${TARGET_COUNT}" -eq 1 ]] || { usage >&2; die "Exactly one --target is required"; }
[[ "${TARGET}" =~ ^(eks|ecs|lambda|agentcore)$ ]] || { usage >&2; die "--target must be eks, ecs, lambda, or agentcore"; }
print_prerequisites "all shared-stage tools plus the selected target's deployment tools"

setup_args=()
security_args=()
${FORCE} && setup_args+=(--force)
${ROTATE} && security_args+=(--rotate-passwords)

"${SCRIPT_DIR}/01-setup.sh" "${setup_args[@]}"
"${SCRIPT_DIR}/02-memory.sh"
"${SCRIPT_DIR}/03-knowledge.sh"
"${SCRIPT_DIR}/04-mcp-server.sh"
"${SCRIPT_DIR}/05-security.sh" "${security_args[@]}"
case "${TARGET}" in
  eks) "${SCRIPT_DIR}/10-deploy-eks.sh" ;;
  ecs) "${SCRIPT_DIR}/11-deploy-ecs.sh" ;;
  lambda) "${SCRIPT_DIR}/12-deploy-lambda.sh" ;;
  agentcore) "${SCRIPT_DIR}/13-deploy-agentcore.sh" ;;
esac
"${SCRIPT_DIR}/20-observability.sh"
"${SCRIPT_DIR}/30-test.sh" --target "${TARGET}"
log "Deployment and tests completed for target: ${TARGET}"
