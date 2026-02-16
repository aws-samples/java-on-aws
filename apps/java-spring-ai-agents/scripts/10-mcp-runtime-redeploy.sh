#!/bin/bash
set -e

echo "=============================================="
echo "10-mcp-runtime-redeploy.sh - MCP Server Redeploy"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${MCP_RUNTIME_ID}" ] || [ -z "${GATEWAY_ID}" ]; then
    echo "Error: Missing required variables. Run 05-mcp-runtime.sh and 06-mcp-gateway.sh first."
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
echo "## Redeploying the MCP server"
echo "1. Build and push the container image"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/backoffice"

aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

cd ~/environment/backoffice
echo "Building container image (this may take a few minutes)..."
mvn -ntp spring-boot:build-image \
    -DskipTests \
    -Dspring-boot.build-image.imageName="${ECR_URI}:latest" \
    -Dspring-boot.build-image.imagePlatform=linux/arm64

echo "Pushing container image to ECR..."
docker push "${ECR_URI}:latest"

## Updating the AgentCore Runtime

echo ""
echo "2. Update the AgentCore Runtime"

aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-id "${MCP_RUNTIME_ID}" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/backoffice-role" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
    --protocol-configuration '{"serverProtocol":"MCP"}' \
    --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
    --authorizer-configuration "{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${GATEWAY_DISCOVERY_URL}\",\"allowedClients\":[\"${GATEWAY_CLIENT_ID}\"]}}" \
    --region ${AWS_REGION} \
    --no-cli-pager

echo -n "Waiting for runtime"
while [ "$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${MCP_RUNTIME_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query 'status' --output text)" != "READY" ]; do
    echo -n "."; sleep 5
done && echo " READY"

## Synchronizing the Gateway target

echo ""
echo "3. Synchronize the Gateway target"

BACKOFFICE_TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
    --query "items[?name=='backoffice'].targetId | [0]" --output text)

aws bedrock-agentcore-control synchronize-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" \
    --target-id-list "${BACKOFFICE_TARGET_ID}" \
    --region ${AWS_REGION} \
    --no-cli-pager

echo "Gateway target synchronized"

echo ""
echo "=============================================="
echo "MCP Server redeploy complete!"
echo "=============================================="
