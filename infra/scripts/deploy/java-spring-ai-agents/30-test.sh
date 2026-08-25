#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

TARGET=""
while (($#)); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || die "--target requires a value"; TARGET="$2"; shift 2 ;;
    -h|--help) echo "Usage: 30-test.sh [--target eks|ecs|lambda|agentcore]"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
print_prerequisites "curl, Cognito credentials in IDE_PASSWORD, and a deployed target"
init_context
load_state
TARGET="${TARGET:-${ACTIVE_TARGET:-}}"
[[ "${TARGET}" =~ ^(eks|ecs|lambda|agentcore)$ ]] || die "No valid target selected"
[[ "${ACTIVE_TARGET:-}" == "${TARGET}" ]] || die "State endpoint belongs to ${ACTIVE_TARGET:-none}, not ${TARGET}"
require_state AIAGENT_ENDPOINT COGNITO_CLIENT_ID COGNITO_USER_POOL_ID MCP_SAMPLE_NAME
[[ -n "${IDE_PASSWORD:-}" ]] || die "IDE_PASSWORD is required to authenticate test user alice"
require_cmd curl

AUTH=$(aws_cli cognito-idp initiate-auth --client-id "${COGNITO_CLIENT_ID}" --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=alice,PASSWORD=${IDE_PASSWORD}" --query AuthenticationResult --output json)
ADMIN_AUTH=$(aws_cli cognito-idp initiate-auth --client-id "${COGNITO_CLIENT_ID}" --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=admin,PASSWORD=${IDE_PASSWORD}" --query AuthenticationResult --output json)
if [[ "${TARGET}" == agentcore ]]; then
  TOKEN=$(jq -r '.AccessToken // empty' <<<"${AUTH}")
  ADMIN_TOKEN=$(jq -r '.AccessToken // empty' <<<"${ADMIN_AUTH}")
  INVOKE_URL="${AIAGENT_ENDPOINT}"
  status=$(aws_cli bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${AGENTCORE_RUNTIME_ID}" --query status --output text)
  [[ "${status}" == READY ]] || die "AgentCore health check failed: ${status}"
else
  TOKEN=$(jq -r '.IdToken // empty' <<<"${AUTH}")
  ADMIN_TOKEN=$(jq -r '.IdToken // empty' <<<"${ADMIN_AUTH}")
  INVOKE_URL="${AIAGENT_ENDPOINT%/}/invocations"
  HEALTH=$(curl --fail-with-body -sS --connect-timeout 10 --max-time 30 "${AIAGENT_ENDPOINT%/}/actuator/health")
  [[ "$(jq -r '.status // empty' <<<"${HEALTH}")" == UP ]] || die "Health endpoint did not report UP"
fi
[[ -n "${TOKEN}" && -n "${ADMIN_TOKEN}" ]] || die "Cognito authentication returned no user or administrator token"

USER_INVOKE_HEADERS=(-H 'Accept: text/plain, text/event-stream')
ADMIN_INVOKE_HEADERS=(-H 'Accept: text/plain, text/event-stream')
if [[ "${TARGET}" == agentcore ]]; then
  require_cmd python3
  USER_RUNTIME_SESSION_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
  ADMIN_RUNTIME_SESSION_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
  USER_INVOKE_HEADERS+=(-H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${USER_RUNTIME_SESSION_ID}")
  ADMIN_INVOKE_HEADERS+=(-H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${ADMIN_RUNTIME_SESSION_ID}")
fi

unauth_status=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 -X POST "${INVOKE_URL}" \
  -H 'Content-Type: application/json' -d '{"prompt":"authentication check"}' || true)
[[ "${unauth_status}" == 401 || "${unauth_status}" == 403 ]] || die "Unauthenticated invocation returned HTTP ${unauth_status}, expected 401 or 403"
log "Health and authentication checks passed"
log "Behavioral tests: persona, conversation memory, PgVector RAG, date/time tool, and MCP inventory"

tmp_dir=$(mktemp -d "${WORK_DIR}/tests.XXXXXX")
trap 'rm -rf "${tmp_dir}"' EXIT
invoke() {
  local name="$1" prompt="$2" output
  output="${tmp_dir}/${name}.txt"
  curl --fail-with-body -sS -N --connect-timeout 10 --max-time 180 -X POST "${INVOKE_URL}" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOKEN}" \
    "${USER_INVOKE_HEADERS[@]}" \
    --data "$(jq -nc --arg prompt "${prompt}" '{prompt:$prompt}')" > "${output}"
  if [[ "${TARGET}" == agentcore ]]; then
    sed 's/^data:[[:space:]]*//' "${output}" | tr -d '\r' > "${output}.normalized"
    mv "${output}.normalized" "${output}"
  fi
  [[ -s "${output}" ]] || die "${name} invocation returned an empty response"
  printf '%s' "${output}"
}
assert_matches() {
  local file="$1" regex="$2" description="$3" response_preview
  if ! grep -Eiq "${regex}" "${file}"; then
    response_preview=$(tr '\n' ' ' < "${file}" | cut -c1-500)
    warn "${description} response: ${response_preview}"
    die "${description} response lacked expected capability evidence"
  fi
}

log "Testing persona: Who are you?"
file=$(invoke persona "Who are you?")
assert_matches "${file}" 'unicorn|rental' "Persona"
log "Persona check passed"

log "Testing conversation memory with two turns"
invoke memory_store "My name is Alex. Please remember it." >/dev/null
file=$(invoke memory_recall "What is my name?")
assert_matches "${file}" '(^|[^[:alpha:]])Alex([^[:alpha:]]|$)' "Conversation memory"
log "Conversation memory check passed"

log "Testing PgVector RAG"
RAG_MARKER="rag-${SUITE_OWNER}-${ACCOUNT_ID}-${AWS_REGION}-v1"
file=$(invoke rag_existing "According to the Unicorn Rentals verification archive, what exact archive marker is associated with unicorn origins?")
if ! grep -Fqi -- "${RAG_MARKER}" "${file}"; then
  RAG_DOCUMENT="Unicorn Rentals verification archive marker ${RAG_MARKER}: unicorn traditions include Chinese Qilin, Indian seals, and Greek accounts."
  curl --fail-with-body -sS -N --connect-timeout 10 --max-time 180 -X POST "${INVOKE_URL}" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${ADMIN_INVOKE_HEADERS[@]}" \
    --data "$(jq -nc --arg prompt "Load verification knowledge." --arg document "${RAG_DOCUMENT}" \
      '{prompt:$prompt,verificationDocument:$document}')" >/dev/null
  for attempt in {1..6}; do
    file=$(invoke "rag_${attempt}" "According to the Unicorn Rentals verification archive, what exact archive marker is associated with unicorn origins?")
    grep -Fqi -- "${RAG_MARKER}" "${file}" && break
    ((attempt == 6)) || sleep 5
  done
else
  log "Stable RAG verification marker is already retrievable; skipping document insertion."
fi
assert_matches "${file}" "${RAG_MARKER}" "PgVector RAG"
log "PgVector RAG check passed"

log "Testing date/time tool"
utc_before=$(date -u +%Y-%m-%dT%H:%M)
file=$(invoke tools "Use the date and time tool to report the current UTC timestamp. Reply with an ISO 8601 timestamp in YYYY-MM-DDTHH:MM:SSZ form.")
utc_after=$(date -u +%Y-%m-%dT%H:%M)
assert_matches "${file}" "(${utc_before}|${utc_after}):[0-5][0-9]Z" "Date/time tool"
log "Date/time tool check passed"

log "Testing MCP Unicorn inventory"
file=$(invoke mcp "Use the Unicorn Store tools and list the available unicorns, including their names.")
assert_matches "${file}" "${MCP_SAMPLE_NAME}|suite.unicorn|classic.small" "MCP"
log "MCP inventory check passed"

log "All hard-failing checks passed: health, auth, persona, memory, RAG, tools, and MCP."
