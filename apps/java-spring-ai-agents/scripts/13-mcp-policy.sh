#!/bin/bash
# Deploy Cedar policies to MCP Gateway
# Creates: Policy Engine, Permit all, Forbid cancelTrip, IAM permissions, Gateway attachment
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

GATEWAY_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:gateway/${MCP_GATEWAY_ID}"

echo "Deploying Cedar policies..."
echo "  Region: ${AWS_REGION}"
echo "  Gateway: ${MCP_GATEWAY_ID}"
echo ""

# Step 1: Create or get Policy Engine
echo "1. Setting up Policy Engine..."
POLICY_ENGINE_ID=$(aws bedrock-agentcore-control list-policy-engines \
    --query 'policyEngines[?name==`BackofficePolicyEngine`].policyEngineId' --output text 2>/dev/null || true)

if [ -z "$POLICY_ENGINE_ID" ]; then
    echo "   Creating new Policy Engine..."
    POLICY_ENGINE_ID=$(aws bedrock-agentcore-control create-policy-engine \
        --name "BackofficePolicyEngine" \
        --query "policyEngineId" --output text)
    
    echo -n "   Waiting for ACTIVE"
    while [ "$(aws bedrock-agentcore-control get-policy-engine --policy-engine-id "${POLICY_ENGINE_ID}" \
        --query 'status' --output text)" != "ACTIVE" ]; do
        echo -n "."; sleep 3
    done
    echo " Done"
else
    echo "   Using existing Policy Engine: ${POLICY_ENGINE_ID}"
fi

POLICY_ENGINE_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:policy-engine/${POLICY_ENGINE_ID}"

# Step 2: Delete existing policies
echo ""
echo "2. Cleaning up existing policies..."
EXISTING=$(aws bedrock-agentcore-control list-policies \
    --policy-engine-id "${POLICY_ENGINE_ID}" \
    --query 'policies[].policyId' --output text 2>/dev/null || true)

for PID in $EXISTING; do
    echo "   Deleting: $PID"
    aws bedrock-agentcore-control delete-policy \
        --policy-engine-id "${POLICY_ENGINE_ID}" \
        --policy-id "$PID" > /dev/null
    
    while true; do
        STATUS=$(aws bedrock-agentcore-control get-policy \
            --policy-engine-id "${POLICY_ENGINE_ID}" \
            --policy-id "$PID" \
            --query 'status' --output text 2>/dev/null || echo "DELETED")
        [ "$STATUS" = "DELETED" ] || [ -z "$STATUS" ] && break
        sleep 2
    done
done
echo "   Done"

# Step 3: Create permit policy (Cedar is deny-by-default)
echo ""
echo "3. Creating permit policy..."
PERMIT_STATEMENT="permit (principal, action, resource == AgentCore::Gateway::\"${GATEWAY_ARN}\");"

PERMIT_ID=$(aws bedrock-agentcore-control create-policy \
    --policy-engine-id "${POLICY_ENGINE_ID}" \
    --name "PermitAllActions" \
    --validation-mode "IGNORE_ALL_FINDINGS" \
    --definition "{\"cedar\":{\"statement\":$(echo "$PERMIT_STATEMENT" | jq -Rs .)}}" \
    --query 'policyId' --output text)

echo "   Policy ID: $PERMIT_ID"

# Step 4: Create forbid policy
echo ""
echo "4. Creating forbid policy..."
FORBID_STATEMENT="forbid (principal, action == AgentCore::Action::\"backoffice___cancelTrip\", resource == AgentCore::Gateway::\"${GATEWAY_ARN}\");"

FORBID_ID=$(aws bedrock-agentcore-control create-policy \
    --policy-engine-id "${POLICY_ENGINE_ID}" \
    --name "ForbidCancelTrip" \
    --validation-mode "IGNORE_ALL_FINDINGS" \
    --definition "{\"cedar\":{\"statement\":$(echo "$FORBID_STATEMENT" | jq -Rs .)}}" \
    --query 'policyId' --output text)

echo "   Policy ID: $FORBID_ID"

# Step 5: Wait for policies to become ACTIVE
echo ""
echo "5. Waiting for policies to become ACTIVE..."
for PID in "$PERMIT_ID" "$FORBID_ID"; do
    for i in {1..30}; do
        STATUS=$(aws bedrock-agentcore-control get-policy \
            --policy-engine-id "${POLICY_ENGINE_ID}" \
            --policy-id "$PID" \
            --query 'status' --output text)
        
        if [ "$STATUS" = "ACTIVE" ]; then
            echo "   $PID: ACTIVE"
            break
        elif [[ "$STATUS" == *"FAILED"* ]]; then
            echo "❌ Policy $PID failed"
            exit 1
        fi
        sleep 2
    done
done

# Step 6: Add IAM permissions for gateway role
echo ""
echo "6. Adding IAM permissions..."
cat > /tmp/policy-permissions.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": "bedrock-agentcore:*",
        "Resource": [
            "${GATEWAY_ARN}",
            "${POLICY_ENGINE_ARN}",
            "${POLICY_ENGINE_ARN}/*"
        ]
    }]
}
EOF

aws iam put-role-policy \
    --role-name mcp-gateway-role \
    --policy-name PolicyEngineAccess \
    --policy-document file:///tmp/policy-permissions.json

echo "   Waiting for IAM propagation..."
sleep 10

# Step 7: Attach policy engine to gateway
echo ""
echo "7. Attaching policy engine to gateway..."
MCP_GATEWAY_ROLE_ARN=$(aws bedrock-agentcore-control get-gateway \
    --gateway-id "${MCP_GATEWAY_ID}" --query 'roleArn' --output text)

aws bedrock-agentcore-control update-gateway \
    --gateway-identifier "${MCP_GATEWAY_ID}" \
    --name "mcp-gateway" \
    --role-arn "${MCP_GATEWAY_ROLE_ARN}" \
    --protocol-type "MCP" \
    --authorizer-type "AWS_IAM" \
    --policy-engine-configuration "{\"arn\":\"${POLICY_ENGINE_ARN}\",\"mode\":\"ENFORCE\"}" \
    --no-cli-pager > /dev/null

echo -n "   Waiting for gateway READY"
while [ "$(aws bedrock-agentcore-control get-gateway --gateway-id "${MCP_GATEWAY_ID}" \
    --query 'status' --output text)" != "READY" ]; do
    echo -n "."; sleep 3
done
echo " Done"

# Save to .env for cleanup script
if ! grep -q "MCP_POLICY_ENGINE_ID" "$SCRIPT_DIR/.env" 2>/dev/null; then
    echo "" >> "$SCRIPT_DIR/.env"
    echo "# Policy Engine" >> "$SCRIPT_DIR/.env"
    echo "MCP_POLICY_ENGINE_ID=${POLICY_ENGINE_ID}" >> "$SCRIPT_DIR/.env"
fi

echo ""
echo "✅ Policies deployed successfully!"
echo ""
echo "Policies:"
aws bedrock-agentcore-control list-policies \
    --policy-engine-id "${POLICY_ENGINE_ID}" \
    --query 'policies[].{Name:name,Status:status}' --output table --no-cli-pager

echo ""
echo "Gateway:"
aws bedrock-agentcore-control get-gateway --gateway-id "${MCP_GATEWAY_ID}" \
    --query '{PolicyEngine:policyEngineConfiguration.arn,Mode:policyEngineConfiguration.mode}' --output table --no-cli-pager
