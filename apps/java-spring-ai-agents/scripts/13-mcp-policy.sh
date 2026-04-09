#!/bin/bash
# Deploy Cedar policy to MCP Gateway
# Requires AWS CLI 2.32+
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

GATEWAY_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:gateway/${MCP_GATEWAY_ID}"
POLICY_FILE="${SCRIPT_DIR}/backoffice-policy.cedar"

echo "Deploying Cedar policy..."
echo "  Gateway: ${MCP_GATEWAY_ID}"
echo "  Policy Engine: ${MCP_POLICY_ENGINE_ID}"
echo ""

# Read and substitute policy
POLICY_STATEMENT=$(sed "s|\${GATEWAY_ARN}|${GATEWAY_ARN}|g" "$POLICY_FILE")

# Delete existing policies and wait for deletion
echo "1. Cleaning up existing policies..."
EXISTING=$(aws bedrock-agentcore-control list-policies \
    --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
    --query 'policies[].policyId' --output text 2>/dev/null || true)

for PID in $EXISTING; do
    echo "   Deleting: $PID"
    aws bedrock-agentcore-control delete-policy \
        --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
        --policy-id "$PID" > /dev/null
    
    # Wait for deletion to complete
    while true; do
        STATUS=$(aws bedrock-agentcore-control get-policy \
            --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
            --policy-id "$PID" \
            --query 'status' --output text 2>/dev/null || echo "DELETED")
        
        if [ "$STATUS" = "DELETED" ] || [ -z "$STATUS" ]; then
            break
        fi
        sleep 2
    done
done

# Create new policy
echo ""
echo "2. Creating policy..."
POLICY_ID=$(aws bedrock-agentcore-control create-policy \
    --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
    --name "ForbidDangerousOperations" \
    --validation-mode "IGNORE_ALL_FINDINGS" \
    --definition "{\"cedar\":{\"statement\":$(echo "$POLICY_STATEMENT" | jq -Rs .)}}" \
    --query 'policyId' --output text)

echo "   Policy ID: $POLICY_ID"

# Wait for ACTIVE
echo ""
echo "3. Waiting for policy to become ACTIVE..."
for i in {1..30}; do
    STATUS=$(aws bedrock-agentcore-control get-policy \
        --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
        --policy-id "$POLICY_ID" \
        --query 'status' --output text)
    
    echo "   Status: $STATUS"
    
    if [ "$STATUS" = "ACTIVE" ]; then
        echo ""
        echo "✅ Policy deployed successfully!"
        exit 0
    elif [[ "$STATUS" == *"FAILED"* ]]; then
        echo ""
        echo "❌ Policy deployment failed"
        exit 1
    fi
    sleep 2
done

echo "❌ Timeout waiting for policy"
exit 1
