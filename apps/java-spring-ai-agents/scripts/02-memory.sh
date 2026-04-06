#!/bin/bash
set -e

echo "=============================================="
echo "02-memory.sh - AgentCore Memory Setup"
echo "=============================================="

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

## Creating the memory resource

# Check if memory already exists in AWS
AGENTCORE_MEMORY_MEMORY_ID=$(aws bedrock-agentcore-control list-memories --no-cli-pager \
    --query "memories[?name=='aiagent_memory'].id | [0]" --output text 2>/dev/null || echo "")

if [ -n "${AGENTCORE_MEMORY_MEMORY_ID}" ] && [ "${AGENTCORE_MEMORY_MEMORY_ID}" != "None" ]; then
    echo "Memory resource already exists: ${AGENTCORE_MEMORY_MEMORY_ID}"
    MEMORY_STATUS=$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
        --no-cli-pager --query 'memory.status' --output text 2>/dev/null || echo "NOT_FOUND")
    echo "Memory resource status: ${MEMORY_STATUS}"
else
    echo ""
    echo "## Creating the memory resource"
    echo "1. Create an AgentCore Memory resource and wait for it to become active (2-5 minutes)"

    AGENTCORE_MEMORY_MEMORY_ID=$(aws bedrock-agentcore-control create-memory \
        --name "aiagent_memory" --event-expiry-duration 7 \
        --no-cli-pager --query "memory.id" --output text)
    echo "Created memory resource: ${AGENTCORE_MEMORY_MEMORY_ID}"

    echo -n "Waiting for memory"
    while [ "$(aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
        --no-cli-pager --query 'memory.status' --output text)" != "ACTIVE" ]; do
        echo -n "."; sleep 5
    done && echo " ACTIVE"
fi

# Write memory config to application.properties
grep -q "agentcore.memory.memory-id" ~/environment/aiagent/src/main/resources/application.properties 2>/dev/null || \
cat >> ~/environment/aiagent/src/main/resources/application.properties << PROPS

# AgentCore Memory
agentcore.memory.memory-id=${AGENTCORE_MEMORY_MEMORY_ID}
agentcore.memory.long-term.auto-discovery=true
PROPS

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

echo ""
echo "=============================================="
echo "Memory setup complete!"
echo "=============================================="
echo ""
echo "Memory ID: ${AGENTCORE_MEMORY_MEMORY_ID}"
echo ""
echo "Application properties written to application.properties:"
echo "  agentcore.memory.memory-id=${AGENTCORE_MEMORY_MEMORY_ID}"
echo "  agentcore.memory.long-term.auto-discovery=true"
