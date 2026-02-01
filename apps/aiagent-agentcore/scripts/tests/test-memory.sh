#!/bin/bash
# ============================================================
# test-memory.sh - Test Memory for a user
# ============================================================
# Usage: ./test-memory.sh [username]
# Example: ./test-memory.sh alice
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
MEMORY_NAME="${APP_NAME}_memory"

USERNAME="${1:-alice}"

echo "=============================================="
echo "Looking up user: ${USERNAME}"
echo "=============================================="

# Find Cognito User Pool
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 50 --region "${REGION}" --no-cli-pager \
  --query "UserPools[?starts_with(Name, '${APP_NAME}')].Id | [0]" --output text 2>/dev/null || echo "")

if [ -z "${USER_POOL_ID}" ] || [ "${USER_POOL_ID}" = "None" ] || [ "${USER_POOL_ID}" = "null" ]; then
  echo "❌ Cognito User Pool not found"
  exit 1
fi
echo "User Pool: ${USER_POOL_ID}"

# Get user sub from Cognito
USER_SUB=$(aws cognito-idp admin-get-user \
  --user-pool-id "${USER_POOL_ID}" \
  --username "${USERNAME}" \
  --region "${REGION}" \
  --no-cli-pager \
  --query "UserAttributes[?Name=='sub'].Value | [0]" --output text 2>/dev/null || echo "")

if [ -z "${USER_SUB}" ] || [ "${USER_SUB}" = "None" ] || [ "${USER_SUB}" = "null" ]; then
  echo "❌ User '${USERNAME}' not found in Cognito"
  exit 1
fi
echo "User Sub: ${USER_SUB}"

# Hash user ID (matches Java implementation)
USER_ID=$(echo -n "${USER_SUB}" | tr -d '-' | cut -c1-25)
echo "User ID (visitorId): ${USER_ID}"

echo "=============================================="
echo "Memory Check for User: ${USERNAME} (${USER_ID})"
echo "=============================================="

# Find memory ID
MEMORY_ID=$(aws bedrock-agentcore-control list-memories --region "${REGION}" --no-cli-pager \
  --query "memories[?starts_with(id, '${MEMORY_NAME}')].id | [0]" --output text 2>/dev/null || echo "")

if [ -z "${MEMORY_ID}" ] || [ "${MEMORY_ID}" = "None" ] || [ "${MEMORY_ID}" = "null" ]; then
  echo "❌ Memory not found. Run ./01-memory.sh first"
  exit 1
fi

echo "Memory ID: ${MEMORY_ID}"

# Get strategy IDs
SEMANTIC_STRATEGY_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
  --query "memory.strategies[?name=='SemanticFacts'].strategyId | [0]" --output text 2>/dev/null || echo "")
PREFERENCE_STRATEGY_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
  --query "memory.strategies[?name=='UserPreferences'].strategyId | [0]" --output text 2>/dev/null || echo "")
SUMMARY_STRATEGY_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
  --query "memory.strategies[?name=='ConversationSummary'].strategyId | [0]" --output text 2>/dev/null || echo "")
EPISODIC_STRATEGY_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
  --query "memory.strategies[?name=='EpisodicMemory'].strategyId | [0]" --output text 2>/dev/null || echo "")

[ "${SEMANTIC_STRATEGY_ID}" = "None" ] && SEMANTIC_STRATEGY_ID=""
[ "${PREFERENCE_STRATEGY_ID}" = "None" ] && PREFERENCE_STRATEGY_ID=""
[ "${SUMMARY_STRATEGY_ID}" = "None" ] && SUMMARY_STRATEGY_ID=""
[ "${EPISODIC_STRATEGY_ID}" = "None" ] && EPISODIC_STRATEGY_ID=""

echo "Strategies:"
echo "  Semantic:    ${SEMANTIC_STRATEGY_ID:-<not configured>}"
echo "  Preferences: ${PREFERENCE_STRATEGY_ID:-<not configured>}"
echo "  Summary:     ${SUMMARY_STRATEGY_ID:-<not configured>}"
echo "  Episodic:    ${EPISODIC_STRATEGY_ID:-<not configured>}"
echo "=============================================="

# Initialize counters
STM_EVENTS=0
STM_MESSAGES=0
LTM_SEMANTIC=0
LTM_PREFERENCES=0
LTM_SUMMARIES=0
LTM_EPISODIC=0

echo ""
echo "=== SESSIONS for User ==="
SESSIONS=$(aws bedrock-agentcore list-sessions \
    --memory-id "${MEMORY_ID}" \
    --actor-id "${USER_ID}" \
    --no-cli-pager 2>/dev/null || echo '{"sessionSummaries":[]}')
echo "${SESSIONS}"
SESSION_COUNT=$(echo "${SESSIONS}" | jq '.sessionSummaries | length' 2>/dev/null || echo 0)
SESSION_IDS=$(echo "${SESSIONS}" | jq -r '.sessionSummaries[].sessionId' 2>/dev/null)

echo ""
echo "=== SHORT-TERM MEMORY (STM) ==="
for SESSION_ID in ${SESSION_IDS}; do
    echo "--- Session: ${SESSION_ID} ---"
    EVENTS=$(aws bedrock-agentcore list-events \
        --memory-id "${MEMORY_ID}" \
        --actor-id "${USER_ID}" \
        --session-id "${SESSION_ID}" \
        --include-payloads \
        --no-cli-pager --no-paginate 2>/dev/null || echo '{"events":[]}')
    echo "${EVENTS}"

    EVENT_COUNT=$(echo "${EVENTS}" | jq '.events | length' 2>/dev/null || echo 0)
    MSG_COUNT=$(echo "${EVENTS}" | jq '[.events[].payload | length] | add // 0' 2>/dev/null || echo 0)
    STM_EVENTS=$((STM_EVENTS + EVENT_COUNT))
    STM_MESSAGES=$((STM_MESSAGES + MSG_COUNT))
done

# LTM - Semantic Facts
if [ -n "${SEMANTIC_STRATEGY_ID}" ]; then
  echo ""
  echo "=== LTM - Semantic Facts ==="
  NAMESPACE="/strategy/${SEMANTIC_STRATEGY_ID}/actors/${USER_ID}"
  SEMANTIC=$(aws bedrock-agentcore list-memory-records \
      --memory-id "${MEMORY_ID}" \
      --namespace "${NAMESPACE}" \
      --memory-strategy-id "${SEMANTIC_STRATEGY_ID}" \
      --no-cli-pager --no-paginate 2>/dev/null || echo '{"memoryRecordSummaries":[]}')
  echo "${SEMANTIC}"
  LTM_SEMANTIC=$(echo "${SEMANTIC}" | jq '.memoryRecordSummaries | length' 2>/dev/null || echo 0)
fi

# LTM - User Preferences
if [ -n "${PREFERENCE_STRATEGY_ID}" ]; then
  echo ""
  echo "=== LTM - User Preferences ==="
  NAMESPACE="/strategy/${PREFERENCE_STRATEGY_ID}/actors/${USER_ID}"
  PREFERENCES=$(aws bedrock-agentcore list-memory-records \
      --memory-id "${MEMORY_ID}" \
      --namespace "${NAMESPACE}" \
      --memory-strategy-id "${PREFERENCE_STRATEGY_ID}" \
      --no-cli-pager --no-paginate 2>/dev/null || echo '{"memoryRecordSummaries":[]}')
  echo "${PREFERENCES}"
  LTM_PREFERENCES=$(echo "${PREFERENCES}" | jq '.memoryRecordSummaries | length' 2>/dev/null || echo 0)
fi

# LTM - Conversation Summaries
if [ -n "${SUMMARY_STRATEGY_ID}" ]; then
  echo ""
  echo "=== LTM - Conversation Summaries ==="
  for SESSION_ID in ${SESSION_IDS}; do
      NAMESPACE="/strategy/${SUMMARY_STRATEGY_ID}/actors/${USER_ID}/sessions/${SESSION_ID}"
      SUMMARIES=$(aws bedrock-agentcore list-memory-records \
          --memory-id "${MEMORY_ID}" \
          --namespace "${NAMESPACE}" \
          --memory-strategy-id "${SUMMARY_STRATEGY_ID}" \
          --no-cli-pager --no-paginate 2>/dev/null || echo '{"memoryRecordSummaries":[]}')
      echo "${SUMMARIES}"
      COUNT=$(echo "${SUMMARIES}" | jq '.memoryRecordSummaries | length' 2>/dev/null || echo 0)
      LTM_SUMMARIES=$((LTM_SUMMARIES + COUNT))
  done
fi

# LTM - Episodic Memory
if [ -n "${EPISODIC_STRATEGY_ID}" ]; then
  echo ""
  echo "=== LTM - Episodic Memory ==="
  NAMESPACE="/strategy/${EPISODIC_STRATEGY_ID}/actors/${USER_ID}"
  EPISODIC=$(aws bedrock-agentcore list-memory-records \
      --memory-id "${MEMORY_ID}" \
      --namespace "${NAMESPACE}" \
      --memory-strategy-id "${EPISODIC_STRATEGY_ID}" \
      --no-cli-pager --no-paginate 2>/dev/null || echo '{"memoryRecordSummaries":[]}')
  echo "${EPISODIC}"
  LTM_EPISODIC=$(echo "${EPISODIC}" | jq '.memoryRecordSummaries | length' 2>/dev/null || echo 0)
fi

# Summary
echo ""
echo "=============================================="
echo "           SUMMARY"
echo "=============================================="
echo "Username:             ${USERNAME}"
echo "User ID:              ${USER_ID}"
echo "Sessions:             ${SESSION_COUNT}"
echo "----------------------------------------------"
echo "STM Events:           ${STM_EVENTS}"
echo "STM Messages:         ${STM_MESSAGES}"
echo "----------------------------------------------"
echo "LTM Semantic:         ${LTM_SEMANTIC}"
echo "LTM Preferences:      ${LTM_PREFERENCES}"
echo "LTM Summaries:        ${LTM_SUMMARIES}"
echo "LTM Episodic:         ${LTM_EPISODIC}"
LTM_TOTAL=$((LTM_SEMANTIC + LTM_PREFERENCES + LTM_SUMMARIES + LTM_EPISODIC))
echo "LTM Total:            ${LTM_TOTAL}"
echo "=============================================="
