#!/bin/bash
set -e

echo "=============================================="
echo "12-aiagent-redeploy.sh - AI Agent Redeploy"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${AIAGENT_RUNTIME_ID}" ]; then
    echo "Error: Missing AIAGENT_RUNTIME_ID. Run 08-aiagent-runtime.sh first."
    exit 1
fi

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Building and pushing the container image

echo ""
echo "## Redeploying the AI agent"
echo "1. Build and push the container image"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent"

aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

cd "${SCRIPT_DIR}/../aiagent"
echo "Building container image (this may take a few minutes)..."
mvn -ntp spring-boot:build-image \
    -Pheadless \
    -DskipTests \
    -Dspring-boot.build-image.imageName="${ECR_URI}:latest" \
    -Dspring-boot.build-image.imagePlatform=linux/arm64

echo "Pushing container image to ECR..."
docker push "${ECR_URI}:latest"

## Updating the AgentCore Runtime

echo ""
echo "2. Update the AgentCore Runtime"

# Build environment variables JSON
cat > /tmp/aiagent-env.json << EOF
{
  "AGENTCORE_MEMORY_MEMORY_ID": "${AGENTCORE_MEMORY_MEMORY_ID}",
  "AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID": "${AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID}",
  "AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID": "${AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID}",
  "SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID": "${SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID}",
  "SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_GATEWAY_URL": "${GATEWAY_URL}"
}
EOF

aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-id "${AIAGENT_RUNTIME_ID}" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-runtime-role" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
    --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
    --authorizer-configuration "{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${AIAGENT_DISCOVERY_URL}\",\"allowedClients\":[\"${AIAGENT_CLIENT_ID}\"]}}" \
    --request-header-configuration '{"requestHeaderAllowlist":["Authorization"]}' \
    --environment-variables file:///tmp/aiagent-env.json \
    --region ${AWS_REGION} \
    --no-cli-pager

rm -f /tmp/aiagent-env.json

echo -n "Waiting for runtime"
while [ "$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${AIAGENT_RUNTIME_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query 'status' --output text)" != "READY" ]; do
    echo -n "."; sleep 5
done && echo " READY"

echo ""
echo "=============================================="
echo "AI Agent redeploy complete!"
echo "=============================================="
echo ""
echo "UI URL: https://${UI_DOMAIN}"
