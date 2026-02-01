#!/bin/bash
# ============================================================
# 01-memory.sh - Deploy AgentCore Memory with STM and LTM
# ============================================================
# Creates Memory resource with 4 LTM strategies:
# - SemanticFacts, UserPreferences, ConversationSummary, EpisodicMemory
# Idempotent - safe to run multiple times
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
MEMORY_NAME="${APP_NAME}_memory"

echo "💾 Creating AgentCore Memory"
echo ""
echo "Region: ${REGION}"
echo "Memory Name: ${MEMORY_NAME}"
echo ""

# ============================================================
# 1. Check/Create Memory Resource
# ============================================================
echo "1️⃣  Checking for existing memory..."
MEMORY_ID=$(aws bedrock-agentcore-control list-memories \
  --region "${REGION}" \
  --no-cli-pager \
  --query "memories[?starts_with(id, '${MEMORY_NAME}')].id | [0]" \
  --output text 2>/dev/null || echo "")

if [ -n "${MEMORY_ID}" ] && [ "${MEMORY_ID}" != "None" ] && [ "${MEMORY_ID}" != "null" ]; then
  echo "   ✓ Memory already exists: ${MEMORY_ID}"

  # Wait for memory to become ACTIVE if still creating
  echo "   Checking memory status..."
  for i in {1..30}; do
    STATUS=$(aws bedrock-agentcore-control get-memory \
      --region "${REGION}" \
      --memory-id "${MEMORY_ID}" \
      --no-cli-pager \
      --query "memory.status" \
      --output text 2>/dev/null || echo "UNKNOWN")

    if [ "${STATUS}" == "ACTIVE" ]; then
      echo "   ✓ Memory is ACTIVE"
      break
    elif [ "${STATUS}" == "FAILED" ]; then
      echo "   ❌ Memory FAILED"
      exit 1
    fi

    if [ $((i % 5)) -eq 0 ]; then
      echo "   ⏳ Status: ${STATUS}"
    fi
    sleep 5
  done
else
  # Create memory resource
  echo "   Creating memory resource..."
  MEMORY_ID=$(aws bedrock-agentcore-control create-memory \
    --region "${REGION}" \
    --name "${MEMORY_NAME}" \
    --description "Memory for AI Agent" \
    --event-expiry-duration 90 \
    --no-cli-pager \
    --query "memory.id" \
    --output text)

  if [ -z "${MEMORY_ID}" ] || [ "${MEMORY_ID}" == "null" ] || [ "${MEMORY_ID}" == "None" ]; then
    echo "   ❌ Failed to create memory"
    exit 1
  fi

  echo "   ✓ Created memory: ${MEMORY_ID}"

  # Wait for memory to become ACTIVE
  echo "   Waiting for memory to become ACTIVE..."
  for i in {1..30}; do
    STATUS=$(aws bedrock-agentcore-control get-memory \
      --region "${REGION}" \
      --memory-id "${MEMORY_ID}" \
      --no-cli-pager \
      --query "memory.status" \
      --output text 2>/dev/null || echo "UNKNOWN")

    if [ "${STATUS}" == "ACTIVE" ]; then
      echo "   ✓ Memory is ACTIVE"
      break
    elif [ "${STATUS}" == "FAILED" ]; then
      echo "   ❌ Memory creation FAILED"
      exit 1
    fi

    if [ $((i % 5)) -eq 0 ]; then
      echo "   ⏳ Status: ${STATUS}"
    fi
    sleep 5
  done
fi

# ============================================================
# 2. Check/Create LTM Strategies
# ============================================================
echo ""
echo "2️⃣  Checking LTM strategies..."
EXISTING_STRATEGIES=$(aws bedrock-agentcore-control get-memory \
  --region "${REGION}" \
  --memory-id "${MEMORY_ID}" \
  --no-cli-pager \
  --query "memory.strategies[].name" \
  --output text 2>/dev/null || echo "")

# Determine which strategies need to be added
SEMANTIC_EXISTS=false
PREFS_EXISTS=false
SUMMARY_EXISTS=false
EPISODIC_EXISTS=false

if [ -n "${EXISTING_STRATEGIES}" ] && [ "${EXISTING_STRATEGIES}" != "None" ]; then
  echo "${EXISTING_STRATEGIES}" | grep -q "SemanticFacts" && SEMANTIC_EXISTS=true
  echo "${EXISTING_STRATEGIES}" | grep -q "UserPreferences" && PREFS_EXISTS=true
  echo "${EXISTING_STRATEGIES}" | grep -q "ConversationSummary" && SUMMARY_EXISTS=true
  echo "${EXISTING_STRATEGIES}" | grep -q "EpisodicMemory" && EPISODIC_EXISTS=true
fi

# Check if all strategies exist
if [ "${SEMANTIC_EXISTS}" = true ] && [ "${PREFS_EXISTS}" = true ] && [ "${SUMMARY_EXISTS}" = true ] && [ "${EPISODIC_EXISTS}" = true ]; then
  echo "   ✓ All 4 LTM strategies already exist"
else
  # Build JSON array of strategies to add
  echo "   Adding missing strategies..."
  STRATEGIES_JSON="["
  FIRST=true

  if [ "${SEMANTIC_EXISTS}" = false ]; then
    [ "${FIRST}" = false ] && STRATEGIES_JSON="${STRATEGIES_JSON},"
    STRATEGIES_JSON="${STRATEGIES_JSON}{\"semanticMemoryStrategy\":{\"name\":\"SemanticFacts\",\"description\":\"Extracts factual information\",\"namespaces\":[\"/strategies/{memoryStrategyId}/actors/{actorId}\"]}}"
    FIRST=false
  fi

  if [ "${PREFS_EXISTS}" = false ]; then
    [ "${FIRST}" = false ] && STRATEGIES_JSON="${STRATEGIES_JSON},"
    STRATEGIES_JSON="${STRATEGIES_JSON}{\"userPreferenceMemoryStrategy\":{\"name\":\"UserPreferences\",\"description\":\"Extracts user preferences\",\"namespaces\":[\"/strategies/{memoryStrategyId}/actors/{actorId}\"]}}"
    FIRST=false
  fi

  if [ "${SUMMARY_EXISTS}" = false ]; then
    [ "${FIRST}" = false ] && STRATEGIES_JSON="${STRATEGIES_JSON},"
    STRATEGIES_JSON="${STRATEGIES_JSON}{\"summaryMemoryStrategy\":{\"name\":\"ConversationSummary\",\"description\":\"Summarizes conversations\",\"namespaces\":[\"/strategies/{memoryStrategyId}/actors/{actorId}/sessions/{sessionId}\"]}}"
    FIRST=false
  fi

  if [ "${EPISODIC_EXISTS}" = false ]; then
    [ "${FIRST}" = false ] && STRATEGIES_JSON="${STRATEGIES_JSON},"
    STRATEGIES_JSON="${STRATEGIES_JSON}{\"episodicMemoryStrategy\":{\"name\":\"EpisodicMemory\",\"description\":\"Captures episodes and reflections\",\"namespaces\":[\"/strategies/{memoryStrategyId}/actors/{actorId}\"],\"reflectionConfiguration\":{\"namespaces\":[\"/strategies/{memoryStrategyId}/actors/{actorId}\"]}}}"
    FIRST=false
  fi

  STRATEGIES_JSON="${STRATEGIES_JSON}]"

  # Add strategies
  aws bedrock-agentcore-control update-memory \
    --region "${REGION}" \
    --memory-id "${MEMORY_ID}" \
    --no-cli-pager \
    --memory-strategies "{\"addMemoryStrategies\":${STRATEGIES_JSON}}" >/dev/null

  # Wait for strategies to become ACTIVE
  echo "   Waiting for strategies to become ACTIVE..."
  for i in {1..30}; do
    STATUSES=$(aws bedrock-agentcore-control get-memory \
      --region "${REGION}" \
      --memory-id "${MEMORY_ID}" \
      --no-cli-pager \
      --query "memory.strategies[].status" \
      --output text 2>/dev/null || echo "UNKNOWN")

    if echo "${STATUSES}" | grep -qv "CREATING"; then
      if echo "${STATUSES}" | grep -q "FAILED"; then
        echo "   ❌ One or more strategies FAILED"
        exit 1
      fi
      echo "   ✓ All strategies ACTIVE"
      break
    fi

    if [ $((i % 5)) -eq 0 ]; then
      echo "   ⏳ Waiting..."
    fi
    sleep 5
  done
fi

# ============================================================
# 3. Get Strategy IDs
# ============================================================
echo ""
echo "3️⃣  Getting strategy IDs..."
SEMANTIC_ID=$(aws bedrock-agentcore-control get-memory \
  --region "${REGION}" \
  --memory-id "${MEMORY_ID}" \
  --no-cli-pager \
  --query "memory.strategies[?name=='SemanticFacts'].strategyId | [0]" \
  --output text)

PREFS_ID=$(aws bedrock-agentcore-control get-memory \
  --region "${REGION}" \
  --memory-id "${MEMORY_ID}" \
  --no-cli-pager \
  --query "memory.strategies[?name=='UserPreferences'].strategyId | [0]" \
  --output text)

SUMMARY_ID=$(aws bedrock-agentcore-control get-memory \
  --region "${REGION}" \
  --memory-id "${MEMORY_ID}" \
  --no-cli-pager \
  --query "memory.strategies[?name=='ConversationSummary'].strategyId | [0]" \
  --output text)

EPISODIC_ID=$(aws bedrock-agentcore-control get-memory \
  --region "${REGION}" \
  --memory-id "${MEMORY_ID}" \
  --no-cli-pager \
  --query "memory.strategies[?name=='EpisodicMemory'].strategyId | [0]" \
  --output text)

echo ""
echo "✅ Memory Created Successfully"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💾 Memory ID: ${MEMORY_ID}"
echo ""
echo "📋 Strategy IDs:"
echo "   Semantic:    ${SEMANTIC_ID}"
echo "   Preferences: ${PREFS_ID}"
echo "   Summary:     ${SUMMARY_ID}"
echo "   Episodic:    ${EPISODIC_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
