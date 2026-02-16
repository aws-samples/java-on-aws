#!/bin/bash
set -e

echo "=============================================="
echo "05-mcp-runtime.sh - MCP Server Runtime Deployment"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run 04-mcp-cognito.sh first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${GATEWAY_POOL_ID}" ] || [ -z "${GATEWAY_CLIENT_ID}" ] || [ -z "${GATEWAY_DISCOVERY_URL}" ]; then
    echo "Error: Missing required environment variables. Run 04-mcp-cognito.sh first."
    exit 1
fi

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Creating the ECR repository

echo ""
echo "## Deploying the MCP server"
echo "1. Create the ECR repository"

# Check if ECR repo exists
ECR_EXISTS=$(aws ecr describe-repositories --repository-names "backoffice" \
    --region ${AWS_REGION} --no-cli-pager 2>/dev/null || echo "")

if [ -n "${ECR_EXISTS}" ]; then
    echo "ECR repository already exists: backoffice"
else
    echo "Creating ECR repository: backoffice"
    aws ecr create-repository \
        --repository-name "backoffice" \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Creating the IAM role

echo ""
echo "2. Create the IAM role"

# Check if role exists
if aws iam get-role --role-name "backoffice-role" --no-cli-pager >/dev/null 2>&1; then
    echo "IAM role already exists: backoffice-role"
else
    echo "Creating IAM role: backoffice-role"

    cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "bedrock-agentcore.amazonaws.com"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"},
      "ArnLike": {"aws:SourceArn": "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:*"}
    }
  }]
}
EOF

    aws iam create-role \
        --role-name "backoffice-role" \
        --permissions-boundary "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --no-cli-pager

    cat > /tmp/backoffice-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:*", "logs:*", "cloudwatch:*"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:*"],
      "Resource": [
        "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/backoffice-*",
        "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/backoffice-*/index/*"
      ]
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "backoffice-role" \
        --policy-name "AgentCorePolicy" \
        --policy-document file:///tmp/backoffice-policy.json \
        --no-cli-pager

    rm -f /tmp/trust-policy.json /tmp/backoffice-policy.json
fi

## Building and pushing the container image

echo ""
echo "3. Build and push the container image"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/backoffice"

aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

cd "${SCRIPT_DIR}/../backoffice"
echo "Building container image (this may take a few minutes)..."
mvn -ntp spring-boot:build-image \
    -DskipTests \
    -Dspring-boot.build-image.imageName="${ECR_URI}:latest" \
    -Dspring-boot.build-image.imagePlatform=linux/arm64

echo "Pushing container image to ECR..."
docker push "${ECR_URI}:latest"

## Getting VPC configuration

echo ""
echo "4. Get VPC configuration"

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=workshop-vpc" \
    --query 'Vpcs[0].VpcId' --output text --no-cli-pager)
echo "VPC: ${VPC_ID}"

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
              "Name=tag:aws-cdk:subnet-type,Values=Private" \
              "Name=availability-zone-id,Values=use1-az1,use1-az2,use1-az4" \
    --query 'Subnets[0].SubnetId' --output text --no-cli-pager)
echo "Subnet: ${SUBNET_ID}"

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
    --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)
echo "Security Group: ${SG_ID}"

# Save VPC config to environment
for VAR in VPC_ID SUBNET_ID SG_ID; do
    if ! grep -q "${VAR}=" ~/environment/.envrc 2>/dev/null; then
        sed -i.bak "/${VAR}=/d" ~/environment/.envrc 2>/dev/null || true
        eval "echo \"export ${VAR}=\${${VAR}}\"" >> ~/environment/.envrc
    fi
done

## Creating the AgentCore Runtime

echo ""
echo "5. Create the AgentCore Runtime"

# Check if runtime already exists
EXISTING_RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region ${AWS_REGION} --no-cli-pager \
    --query "agentRuntimeSummaries[?agentRuntimeName=='backoffice'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_RUNTIME_ID}" != "None" ] && [ -n "${EXISTING_RUNTIME_ID}" ]; then
    echo "AgentCore Runtime already exists: ${EXISTING_RUNTIME_ID}"
    MCP_RUNTIME_ID="${EXISTING_RUNTIME_ID}"
else
    echo "Creating AgentCore Runtime: backoffice"

    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/backoffice-role"

    MCP_RUNTIME_ID=$(aws bedrock-agentcore-control create-agent-runtime \
        --agent-runtime-name "backoffice" \
        --role-arn "${ROLE_ARN}" \
        --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
        --protocol-configuration '{"serverProtocol":"MCP"}' \
        --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
        --authorizer-configuration "{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${GATEWAY_DISCOVERY_URL}\",\"allowedClients\":[\"${GATEWAY_CLIENT_ID}\"]}}" \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'agentRuntimeId' --output text)

    echo -n "Waiting for runtime"
    while [ "$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "${MCP_RUNTIME_ID}" --region ${AWS_REGION} \
        --no-cli-pager --query 'status' --output text)" != "READY" ]; do
        echo -n "."; sleep 5
    done && echo " READY"
fi

# Save runtime ID to environment
if ! grep -q "MCP_RUNTIME_ID=${MCP_RUNTIME_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/MCP_RUNTIME_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export MCP_RUNTIME_ID=${MCP_RUNTIME_ID}" >> ~/environment/.envrc
fi

## Saving endpoint and token URI

echo ""
echo "6. Save endpoint and token URI"

RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${MCP_RUNTIME_ID}"
MCP_ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)/invocations?qualifier=DEFAULT"
COGNITO_DOMAIN=$(aws cognito-idp describe-user-pool \
    --user-pool-id "${GATEWAY_POOL_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query 'UserPool.Domain' --output text)
M2M_TOKEN_URI="https://${COGNITO_DOMAIN}.auth.${AWS_REGION}.amazoncognito.com/oauth2/token"

# Save to environment
for VAR in MCP_ENDPOINT M2M_TOKEN_URI; do
    sed -i.bak "/${VAR}=/d" ~/environment/.envrc 2>/dev/null || true
    eval "echo \"export ${VAR}=\${${VAR}}\"" >> ~/environment/.envrc
done

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "MCP Server Runtime deployment complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  MCP_RUNTIME_ID=${MCP_RUNTIME_ID}"
echo "  MCP_ENDPOINT=${MCP_ENDPOINT}"
echo "  M2M_TOKEN_URI=${M2M_TOKEN_URI}"
