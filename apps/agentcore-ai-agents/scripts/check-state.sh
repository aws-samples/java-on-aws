#!/bin/bash
# Check the end state of module 1000 (AgentCore Runtime) that the modules from 1100 on start from.
# The list matches docs/STATE-CONTRACT.md. Read-only: AWS describe/list calls and one HTTPS request to the UI.
# Prints one line per check and the framework of ~/environment/aiagent; exits 1 if a check fails.
set -uo pipefail
[ -f ~/environment/.envrc ] && source ~/environment/.envrc
REGION="${AWS_REGION:-us-east-1}"
CTL="aws bedrock-agentcore-control --region ${REGION} --no-cli-pager"
FAILED=0

check() {  # check NAME COMMAND...: passes when COMMAND succeeds
  local name="$1"; shift
  if "$@" > /dev/null 2>&1; then echo "ok      ${name}"; else echo "MISSING ${name}"; FAILED=1; fi
}
equals() {  # equals EXPECTED COMMAND...: passes when COMMAND prints EXPECTED (tabs count as spaces)
  local expected="$1"; shift
  [ "$("$@" 2>/dev/null | tr -s '\t ' ' ')" = "${expected}" ]
}

echo "== ~/environment/.envrc"
for var in ACCOUNT_ID AWS_REGION IDE_PASSWORD FRAMEWORK AGENTCORE_MEMORY_ID KNOWLEDGE_BASE_ID ARTIFACTS_BUCKET PORTAL_URL \
    GATEWAY_POOL_ID GATEWAY_CLIENT_ID GATEWAY_DISCOVERY_URL VPC_ID SUBNET_ID SG_ID MCP_RUNTIME_ID MCP_ENDPOINT \
    M2M_TOKEN_URI GATEWAY_ID GATEWAY_URL AIAGENT_USER_POOL_ID AIAGENT_DISCOVERY_URL AIAGENT_CLIENT_ID \
    COGNITO_ISSUER_URI AIAGENT_RUNTIME_ID AIAGENT_ENDPOINT UI_BUCKET UI_DOMAIN; do
  check "${var}" test -n "${!var:-}"
done

echo "== AWS resources"
check "memory ${AGENTCORE_MEMORY_ID:-} ACTIVE, 2 strategies" equals "ACTIVE 2" \
  ${CTL} get-memory --memory-id "${AGENTCORE_MEMORY_ID:-none}" --query '[memory.status, length(memory.strategies)]' --output text
check "knowledge base aiagent-kb ACTIVE" equals "ACTIVE" \
  aws bedrock-agent get-knowledge-base --region "${REGION}" --knowledge-base-id "${KNOWLEDGE_BASE_ID:-none}" --query 'knowledgeBase.status' --output text
check "runtime backoffice READY" equals "READY" \
  ${CTL} get-agent-runtime --agent-runtime-id "${MCP_RUNTIME_ID:-none}" --query status --output text
check "runtime aiagent READY" equals "READY" \
  ${CTL} get-agent-runtime --agent-runtime-id "${AIAGENT_RUNTIME_ID:-none}" --query status --output text
check "gateway mcp-gateway READY" equals "READY" \
  ${CTL} get-gateway --gateway-identifier "${GATEWAY_ID:-none}" --query status --output text
for target in backoffice holidays; do
  check "gateway target ${target} READY" equals "READY" \
    ${CTL} list-gateway-targets --gateway-identifier "${GATEWAY_ID:-none}" --query "items[?name=='${target}'].status | [0]" --output text
done
for user in admin alice bob; do
  check "Cognito user ${user}" aws cognito-idp admin-get-user --region "${REGION}" \
    --user-pool-id "${AIAGENT_USER_POOL_ID:-none}" --username "${user}"
done
check "DynamoDB table backoffice-trip ACTIVE" equals "ACTIVE" \
  aws dynamodb describe-table --region "${REGION}" --table-name backoffice-trip --query 'Table.TableStatus' --output text
for repo in aiagent backoffice; do
  check "ECR repository ${repo}" aws ecr describe-repositories --region "${REGION}" --repository-names "${repo}"
done
for role in aiagent-kb-role backoffice-role mcp-gateway-role aiagent-runtime-role; do
  check "IAM role ${role}" aws iam get-role --role-name "${role}"
done
check "Transaction Search (spans to CloudWatch Logs) ACTIVE" equals "CloudWatchLogs ACTIVE" \
  aws xray get-trace-segment-destination --region "${REGION}" --query '[Destination, Status]' --output text
check "UI https://${UI_DOMAIN:-none}" equals "200" curl -s -o /dev/null -w "%{http_code}" "https://${UI_DOMAIN:-none}"

echo "== Working copies"
APP=~/environment/aiagent
if [ ! -d "${APP}" ]; then DETECTED=unknown; MAIN="${APP}"
elif [ -f "${APP}/pom.xml" ]; then DETECTED=java-spring-ai; MAIN="${APP}/src/main/java/com/example/agent/SecurityConfig.java"
elif [ -f "${APP}/package.json" ]; then DETECTED=ts-vercel; MAIN="${APP}/auth.ts"
elif grep -qs langgraph "${APP}/pyproject.toml"; then DETECTED=python-langgraph; MAIN="${APP}/auth.py"
else DETECTED=python-strands; MAIN="${APP}/auth.py"; fi
check "~/environment/aiagent at the deploy module (${DETECTED})" test -f "${MAIN}"
check "~/environment/aiagent matches FRAMEWORK=${FRAMEWORK:-}" test "${DETECTED}" = "${FRAMEWORK:-}"
check "~/environment/backoffice" test -d ~/environment/backoffice

echo "framework: ${DETECTED}"
if [ "${FAILED}" = "0" ]; then echo "End state complete"; else echo "End state incomplete"; fi
exit "${FAILED}"
