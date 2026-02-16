#!/bin/bash
set -e

echo "=============================================="
echo "02-memory.sh - AgentCore Memory Setup"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Creating ~/environment/.envrc"
    mkdir -p ~/environment
    touch ~/environment/.envrc
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

## Creating the memory resource

# Check if memory already exists
if [ -n "${AGENTCORE_MEMORY_MEMORY_ID}" ]; then
    echo "Memory resource already exists: ${AGENTCORE_MEMORY_MEMORY_ID}"
    MEMORY_STATUS=$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
        --no-cli-pager --query 'memory.status' --output text 2>/dev/null || echo "NOT_FOUND")

    if [ "$MEMORY_STATUS" = "ACTIVE" ]; then
        echo "Memory resource is ACTIVE, skipping creation"
    elif [ "$MEMORY_STATUS" = "NOT_FOUND" ]; then
        echo "Memory resource not found, will create new one"
        unset AGENTCORE_MEMORY_MEMORY_ID
    else
        echo "Memory resource status: $MEMORY_STATUS"
    fi
fi

if [ -z "${AGENTCORE_MEMORY_MEMORY_ID}" ]; then
    echo ""
    echo "## Creating the memory resource"
    echo "1. Create an AgentCore Memory resource and wait for it to become active (2-5 minutes)"

    AGENTCORE_MEMORY_MEMORY_ID=$(aws bedrock-agentcore-control create-memory \
        --name "aiagent_memory" --event-expiry-duration 7 \
        --no-cli-pager --query "memory.id" --output text)
    echo "export AGENTCORE_MEMORY_MEMORY_ID=${AGENTCORE_MEMORY_MEMORY_ID}" >> ~/environment/.envrc
    echo "Created memory resource: ${AGENTCORE_MEMORY_MEMORY_ID}"

    echo -n "Waiting for memory"
    while [ "$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
        --no-cli-pager --query 'memory.status' --output text)" != "ACTIVE" ]; do
        echo -n "."; sleep 5
    done && echo " ACTIVE"
fi

## Adding LTM strategies

# Check if strategies already exist
EXISTING_STRATEGIES=$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
    --no-cli-pager --query 'length(memory.strategies)' --output text 2>/dev/null || echo "0")

if [ "$EXISTING_STRATEGIES" -ge 2 ]; then
    echo ""
    echo "LTM strategies already configured (${EXISTING_STRATEGIES} strategies found)"
else
    echo ""
    echo "2. Add LTM strategies and wait for them to become active"

    aws bedrock-agentcore-control update-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" --no-cli-pager \
        --memory-strategies '{
            "addMemoryStrategies": [
                {"semanticMemoryStrategy": {"name": "SemanticFacts", "namespaces": ["/strategies/{memoryStrategyId}/actors/{actorId}"]}},
                {"userPreferenceMemoryStrategy": {"name": "UserPreferences", "namespaces": ["/strategies/{memoryStrategyId}/actors/{actorId}"]}}
            ]
        }'

    echo -n "Waiting for strategies"
    while aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
        --no-cli-pager --query 'memory.strategies[].status' --output text | grep -q "CREATING"; do
        echo -n "."; sleep 5
    done && echo " ACTIVE"
fi

## Getting strategy IDs

echo ""
echo "3. Get strategy IDs and save to environment file"

SEMANTIC_ID=$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
    --no-cli-pager --query "memory.strategies[?name=='SemanticFacts'].strategyId | [0]" --output text)
PREFS_ID=$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
    --no-cli-pager --query "memory.strategies[?name=='UserPreferences'].strategyId | [0]" --output text)

# Update .envrc only if values changed
if ! grep -q "AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID=${SEMANTIC_ID}" ~/environment/.envrc 2>/dev/null; then
    # Remove old entries if they exist
    sed -i.bak '/AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID/d' ~/environment/.envrc 2>/dev/null || true
    echo "export AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID=${SEMANTIC_ID}" >> ~/environment/.envrc
fi

if ! grep -q "AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID=${PREFS_ID}" ~/environment/.envrc 2>/dev/null; then
    # Remove old entries if they exist
    sed -i.bak '/AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID/d' ~/environment/.envrc 2>/dev/null || true
    echo "export AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID=${PREFS_ID}" >> ~/environment/.envrc
fi

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "Memory setup complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  AGENTCORE_MEMORY_MEMORY_ID=${AGENTCORE_MEMORY_MEMORY_ID}"
echo "  AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID=${SEMANTIC_ID}"
echo "  AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID=${PREFS_ID}"
