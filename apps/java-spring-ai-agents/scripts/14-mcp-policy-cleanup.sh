#!/bin/bash
# Cleanup Cedar policies from MCP Gateway
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

echo "Cleaning up policies from engine: ${MCP_POLICY_ENGINE_ID}"
echo ""

POLICIES=$(aws bedrock-agentcore-control list-policies \
    --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
    --query 'policies[].policyId' --output text 2>/dev/null || true)

if [ -z "$POLICIES" ]; then
    echo "No policies found."
    exit 0
fi

for PID in $POLICIES; do
    echo "Deleting: $PID"
    aws bedrock-agentcore-control delete-policy \
        --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
        --policy-id "$PID" > /dev/null
    
    echo "  Waiting for deletion..."
    while true; do
        STATUS=$(aws bedrock-agentcore-control get-policy \
            --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
            --policy-id "$PID" \
            --query 'status' --output text 2>/dev/null || echo "DELETED")
        
        if [ "$STATUS" = "DELETED" ] || [ -z "$STATUS" ]; then
            echo "  ✅ Deleted"
            break
        fi
        echo "  Status: $STATUS"
        sleep 2
    done
done

echo ""
echo "✅ All policies cleaned up!"
