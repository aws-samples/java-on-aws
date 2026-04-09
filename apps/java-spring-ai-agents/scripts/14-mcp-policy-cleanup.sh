#!/bin/bash
# Remove Cedar policies from MCP Gateway
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Set defaults if not in .env
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
ACCOUNT_ID=${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}

# Get gateway ID if not set
if [ -z "$MCP_GATEWAY_ID" ]; then
    MCP_GATEWAY_ID=$(aws bedrock-agentcore-control list-gateways --query 'items[0].gatewayId' --output text)
fi

# Get policy engine ID if not set
if [ -z "$MCP_POLICY_ENGINE_ID" ]; then
    MCP_POLICY_ENGINE_ID=$(aws bedrock-agentcore-control list-policy-engines \
        --query 'policyEngines[?name==`BackofficePolicyEngine`].policyEngineId' --output text 2>/dev/null || true)
fi

if [ -z "$MCP_POLICY_ENGINE_ID" ]; then
    echo "No policy engine found."
    exit 0
fi

echo "Removing Cedar policies..."
echo "  Gateway: ${MCP_GATEWAY_ID}"
echo "  Policy Engine: ${MCP_POLICY_ENGINE_ID}"
echo ""

# Step 1: Detach policy engine from gateway
echo "1. Detaching policy engine from gateway..."
CURRENT_POLICY=$(aws bedrock-agentcore-control get-gateway --gateway-id "${MCP_GATEWAY_ID}" \
    --query 'policyEngineConfiguration.arn' --output text 2>/dev/null || echo "None")

if [ "$CURRENT_POLICY" != "None" ] && [ -n "$CURRENT_POLICY" ]; then
    MCP_GATEWAY_ROLE_ARN=$(aws bedrock-agentcore-control get-gateway \
        --gateway-id "${MCP_GATEWAY_ID}" --query 'roleArn' --output text)
    
    aws bedrock-agentcore-control update-gateway \
        --gateway-identifier "${MCP_GATEWAY_ID}" \
        --name "mcp-gateway" \
        --role-arn "${MCP_GATEWAY_ROLE_ARN}" \
        --protocol-type "MCP" \
        --authorizer-type "AWS_IAM" \
        --no-cli-pager > /dev/null
    
    echo -n "   Waiting for gateway READY"
    while [ "$(aws bedrock-agentcore-control get-gateway --gateway-id "${MCP_GATEWAY_ID}" \
        --query 'status' --output text)" != "READY" ]; do
        echo -n "."; sleep 3
    done
    echo " Done"
else
    echo "   No policy engine attached to gateway"
fi

# Step 2: Delete all policies
echo ""
echo "2. Deleting policies..."
EXISTING=$(aws bedrock-agentcore-control list-policies \
    --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
    --query 'policies[].policyId' --output text 2>/dev/null || true)

if [ -z "$EXISTING" ]; then
    echo "   No policies to delete."
else
    for PID in $EXISTING; do
        echo "   Deleting: $PID"
        aws bedrock-agentcore-control delete-policy \
            --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
            --policy-id "$PID" > /dev/null
        
        while true; do
            STATUS=$(aws bedrock-agentcore-control get-policy \
                --policy-engine-id "${MCP_POLICY_ENGINE_ID}" \
                --policy-id "$PID" \
                --query 'status' --output text 2>/dev/null || echo "DELETED")
            [ "$STATUS" = "DELETED" ] || [ -z "$STATUS" ] && break
            sleep 2
        done
    done
fi

echo ""
echo "✅ Policies removed. Gateway restored to full tool access."
