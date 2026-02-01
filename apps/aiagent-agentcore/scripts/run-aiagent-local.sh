#!/bin/bash
# ============================================================
# Run AI Agent locally
# ============================================================
# Auto-detects Memory, KB, Cognito
# Idempotent - safe to run multiple times
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../aiagent"

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
MEMORY_NAME="${APP_NAME}_memory"
KB_NAME="${APP_NAME}-kb"
COGNITO_POOL="${APP_NAME}-user-pool"

echo "🚀 Starting AI Agent Locally"
echo ""

# ============================================================
# 1. Check for Cognito
# ============================================================
echo "Checking for Cognito..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "${REGION}" --no-cli-pager \
  --query "UserPools[?Name=='${COGNITO_POOL}'].Id | [0]" --output text 2>/dev/null || echo "")
[ "${USER_POOL_ID}" = "None" ] && USER_POOL_ID=""

CONFIG_FILE="${PROJECT_DIR}/src/main/resources/static/config.json"
[ ! -f "${CONFIG_FILE}" ] && echo '{}' > "${CONFIG_FILE}"

if [ -n "${USER_POOL_ID}" ]; then
  ISSUER_URI="https://cognito-idp.${REGION}.amazonaws.com/${USER_POOL_ID}"
  CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
    --user-pool-id "${USER_POOL_ID}" \
    --region "${REGION}" \
    --no-cli-pager \
    --query "UserPoolClients[?ClientName=='${APP_NAME}-client'].ClientId | [0]" \
    --output text 2>/dev/null || echo "")
  [ "${CLIENT_ID}" = "None" ] && CLIENT_ID=""

  echo "   ✓ Found Cognito: ${USER_POOL_ID}"
  echo ""
  printf "Use Cognito security? [Enter=yes, any other key=no]: "
  IFS= read -r -n 1 USE_COGNITO
  echo ""
  if [ "${USE_COGNITO}" = "" ]; then
    export SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI="${ISSUER_URI}"
    jq --arg userPoolId "${USER_POOL_ID}" \
       --arg clientId "${CLIENT_ID}" \
       '. + {userPoolId: $userPoolId, clientId: $clientId}' \
       "${CONFIG_FILE}" > /tmp/config.json && mv /tmp/config.json "${CONFIG_FILE}"
    echo "   ✓ Security ENABLED"
  else
    jq 'del(.userPoolId, .clientId)' "${CONFIG_FILE}" > /tmp/config.json && mv /tmp/config.json "${CONFIG_FILE}"
    echo "   ⚠️  Security DISABLED"
  fi
else
  jq 'del(.userPoolId, .clientId)' "${CONFIG_FILE}" > /tmp/config.json && mv /tmp/config.json "${CONFIG_FILE}"
  echo "   ⚠️  Cognito not found"
fi

# ============================================================
# 2. Check for Memory
# ============================================================
echo ""
echo "Checking for Memory..."
MEMORY_ID=$(aws bedrock-agentcore-control list-memories --region "${REGION}" --no-cli-pager \
  --query "memories[?starts_with(id, '${MEMORY_NAME}')].id | [0]" --output text 2>/dev/null || echo "")
[ "${MEMORY_ID}" = "None" ] && MEMORY_ID=""

if [ -n "${MEMORY_ID}" ]; then
  echo "   ✓ Found Memory: ${MEMORY_ID}"
  export AGENTCORE_MEMORY_MEMORY_ID="${MEMORY_ID}"

  # Get strategy IDs
  SEMANTIC_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='SemanticFacts'].strategyId | [0]" --output text 2>/dev/null || echo "")
  PREFS_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='UserPreferences'].strategyId | [0]" --output text 2>/dev/null || echo "")
  SUMMARY_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='ConversationSummary'].strategyId | [0]" --output text 2>/dev/null || echo "")
  EPISODIC_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='EpisodicMemory'].strategyId | [0]" --output text 2>/dev/null || echo "")

  HAS_LTM=false
  [ "${SEMANTIC_ID}" != "None" ] && [ -n "${SEMANTIC_ID}" ] && export AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID="${SEMANTIC_ID}" && HAS_LTM=true
  [ "${PREFS_ID}" != "None" ] && [ -n "${PREFS_ID}" ] && export AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID="${PREFS_ID}" && HAS_LTM=true
  [ "${SUMMARY_ID}" != "None" ] && [ -n "${SUMMARY_ID}" ] && export AGENTCORE_MEMORY_LONG_TERM_SUMMARY_STRATEGY_ID="${SUMMARY_ID}" && HAS_LTM=true
  [ "${EPISODIC_ID}" != "None" ] && [ -n "${EPISODIC_ID}" ] && export AGENTCORE_MEMORY_LONG_TERM_EPISODIC_STRATEGY_ID="${EPISODIC_ID}" && HAS_LTM=true

  echo "   ✓ STM enabled"
  [ "${HAS_LTM}" = true ] && echo "   ✓ LTM enabled"
else
  echo "   ⚠️  Memory not found"
fi

# ============================================================
# 3. Check for KB
# ============================================================
echo ""
echo "Checking for Knowledge Base..."
KB_ID=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
  --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null || echo "")
[ "${KB_ID}" = "None" ] && KB_ID=""

if [ -n "${KB_ID}" ]; then
  echo "   ✓ Found KB: ${KB_ID}"
  export SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID="${KB_ID}"
else
  echo "   ⚠️  KB not found"
fi

# ============================================================
# 4. Build and Start
# ============================================================
echo ""
echo "Building application..."
mvn -f "${PROJECT_DIR}/pom.xml" package -DskipTests -q
echo "   ✓ Built"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting app on http://localhost:8080"
echo "UI: http://localhost:8080"
[ -n "${SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI}" ] && echo "Security: Cognito JWT validation enabled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

mvn -f "${PROJECT_DIR}/pom.xml" spring-boot:run -DskipTests
