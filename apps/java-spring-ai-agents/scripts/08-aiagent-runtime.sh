#!/bin/bash
set -e

echo "=============================================="
echo "08-aiagent-runtime.sh - AI Agent Runtime Deployment"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${AIAGENT_USER_POOL_ID}" ] || [ -z "${AIAGENT_CLIENT_ID}" ] || [ -z "${AIAGENT_DISCOVERY_URL}" ]; then
    echo "Error: Missing Cognito variables. Run 07-aiagent-cognito.sh first."
    exit 1
fi

if [ -z "${AGENTCORE_MEMORY_MEMORY_ID}" ]; then
    echo "Error: Missing Memory variables. Run 02-memory.sh first."
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
echo "## Deploying the AI agent to AgentCore Runtime"
echo "1. Create the ECR repository"

# Check if ECR repo exists
ECR_EXISTS=$(aws ecr describe-repositories --repository-names "aiagent" \
    --region ${AWS_REGION} --no-cli-pager 2>/dev/null || echo "")

if [ -n "${ECR_EXISTS}" ]; then
    echo "ECR repository already exists: aiagent"
else
    echo "Creating ECR repository: aiagent"
    aws ecr create-repository \
        --repository-name "aiagent" \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Creating the IAM role

echo ""
echo "2. Create the IAM role"

# Check if role exists
if aws iam get-role --role-name "aiagent-runtime-role" --no-cli-pager >/dev/null 2>&1; then
    echo "IAM role already exists: aiagent-runtime-role"
else
    echo "Creating IAM role: aiagent-runtime-role"

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
        --role-name "aiagent-runtime-role" \
        --permissions-boundary "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --no-cli-pager

    cat > /tmp/aiagent-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["bedrock:*", "bedrock-agentcore:*", "aws-marketplace:*"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["ecr:*", "logs:*", "xray:*", "cloudwatch:*"],
      "Resource": "*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "aiagent-runtime-role" \
        --policy-name "AgentCoreExecutionPolicy" \
        --policy-document file:///tmp/aiagent-policy.json \
        --no-cli-pager

    rm -f /tmp/trust-policy.json /tmp/aiagent-policy.json
fi

## Building and pushing the container image

echo ""
echo "3. Build and push the container image"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent"

aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

cd ~/environment/aiagent
echo "Building container image (this may take a few minutes)..."
mvn -ntp spring-boot:build-image \
    -Pheadless \
    -DskipTests \
    -Dspring-boot.build-image.imageName="${ECR_URI}:latest" \
    -Dspring-boot.build-image.imagePlatform=linux/arm64

echo "Pushing container image to ECR..."
docker push "${ECR_URI}:latest"

## Getting VPC configuration

echo ""
echo "4. Get VPC configuration"

if [ -z "${VPC_ID}" ] || [ -z "${SUBNET_ID}" ] || [ -z "${SG_ID}" ]; then
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
        sed -i.bak "/${VAR}=/d" ~/environment/.envrc 2>/dev/null || true
        eval "echo \"export ${VAR}=\${${VAR}}\"" >> ~/environment/.envrc
    done
else
    echo "Using existing VPC configuration"
    echo "VPC: ${VPC_ID}"
    echo "Subnet: ${SUBNET_ID}"
    echo "Security Group: ${SG_ID}"
fi

## Creating the AgentCore Runtime

echo ""
echo "5. Create the AgentCore Runtime"

# Check if runtime already exists
EXISTING_RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region ${AWS_REGION} --no-cli-pager \
    --query "agentRuntimeSummaries[?agentRuntimeName=='aiagent'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_RUNTIME_ID}" != "None" ] && [ -n "${EXISTING_RUNTIME_ID}" ]; then
    echo "AgentCore Runtime already exists: ${EXISTING_RUNTIME_ID}"
    AIAGENT_RUNTIME_ID="${EXISTING_RUNTIME_ID}"
else
    echo "Creating AgentCore Runtime: aiagent"

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

    AIAGENT_RUNTIME_ID=$(aws bedrock-agentcore-control create-agent-runtime \
        --agent-runtime-name "aiagent" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-runtime-role" \
        --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
        --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
        --authorizer-configuration "{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${AIAGENT_DISCOVERY_URL}\",\"allowedClients\":[\"${AIAGENT_CLIENT_ID}\"]}}" \
        --request-header-configuration '{"requestHeaderAllowlist":["Authorization"]}' \
        --environment-variables file:///tmp/aiagent-env.json \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'agentRuntimeId' --output text)

    rm -f /tmp/aiagent-env.json

    echo -n "Waiting for runtime"
    while [ "$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "${AIAGENT_RUNTIME_ID}" --region ${AWS_REGION} \
        --no-cli-pager --query 'status' --output text)" != "READY" ]; do
        echo -n "."; sleep 5
    done && echo " READY"
fi

# Save runtime ID to environment
if ! grep -q "AIAGENT_RUNTIME_ID=${AIAGENT_RUNTIME_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/AIAGENT_RUNTIME_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export AIAGENT_RUNTIME_ID=${AIAGENT_RUNTIME_ID}" >> ~/environment/.envrc
fi

## Saving endpoint

echo ""
echo "6. Save endpoint"

RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${AIAGENT_RUNTIME_ID}"
AIAGENT_ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)/invocations?qualifier=DEFAULT"

# Save to environment
sed -i.bak '/AIAGENT_ENDPOINT=/d' ~/environment/.envrc 2>/dev/null || true
echo "export AIAGENT_ENDPOINT=${AIAGENT_ENDPOINT}" >> ~/environment/.envrc

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "AI Agent Runtime deployment complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  AIAGENT_RUNTIME_ID=${AIAGENT_RUNTIME_ID}"
echo "  AIAGENT_ENDPOINT=${AIAGENT_ENDPOINT}"
