#!/bin/bash
set -e

# Accept folder name as parameter (default: aiagent)
AGENT_NAME="${1:-aiagent}"
RUNTIME_NAME=$(echo "${AGENT_NAME}" | tr '-' '_')
VAR_PREFIX=$(echo "${AGENT_NAME}" | tr '[:lower:]-' '[:upper:]_')

echo "=============================================="
echo "aiagent-runtime.sh - AI Agent Runtime Deployment"
echo "Agent: ${AGENT_NAME}"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables for main agent
if [ "${AGENT_NAME}" = "aiagent" ]; then
    if [ -z "${AIAGENT_USER_POOL_ID}" ] || [ -z "${AIAGENT_CLIENT_ID}" ] || [ -z "${AIAGENT_DISCOVERY_URL}" ]; then
        echo "Error: Missing Cognito variables. Run 07-aiagent-cognito.sh first."
        exit 1
    fi
fi

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

## Creating the ECR repository

echo ""
echo "## Deploying the AI agent to AgentCore Runtime"
echo "1. Create the ECR repository"

ECR_EXISTS=$(aws ecr describe-repositories --repository-names "${AGENT_NAME}" \
    --region ${AWS_REGION} --no-cli-pager 2>/dev/null || echo "")

if [ -n "${ECR_EXISTS}" ]; then
    echo "ECR repository already exists: ${AGENT_NAME}"
else
    echo "Creating ECR repository: ${AGENT_NAME}"
    aws ecr create-repository \
        --repository-name "${AGENT_NAME}" \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Creating the IAM role

echo ""
echo "2. Create the IAM role"

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
      "Action": ["ecr:*", "logs:*", "xray:*", "cloudwatch:*", "s3:*"],
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

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${AGENT_NAME}"

aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

cd ~/environment/${AGENT_NAME}

echo "Building container image (this may take a few minutes)..."

MVN_PROFILES=""
if [ "${AGENT_NAME}" = "aiagent" ]; then
    MVN_PROFILES="-Pheadless"
fi

mvn -ntp spring-boot:build-image \
    ${MVN_PROFILES} \
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

# JWT authorizer for main agent (has UI), IAM-only for sub-agents
if [ "${AGENT_NAME}" = "aiagent" ]; then
    AUTH_ARGS="--authorizer-configuration {\"customJWTAuthorizer\":{\"discoveryUrl\":\"${AIAGENT_DISCOVERY_URL}\",\"allowedClients\":[\"${AIAGENT_CLIENT_ID}\"]}} --request-header-configuration {\"requestHeaderAllowlist\":[\"Authorization\"]}"
else
    AUTH_ARGS=""
fi

EXISTING_RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region ${AWS_REGION} --no-cli-pager \
    --query "agentRuntimes[?agentRuntimeName=='${RUNTIME_NAME}'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_RUNTIME_ID}" != "None" ] && [ -n "${EXISTING_RUNTIME_ID}" ]; then
    echo "AgentCore Runtime already exists: ${EXISTING_RUNTIME_ID}"
    echo "Updating runtime with latest configuration..."
    AGENT_RUNTIME_ID="${EXISTING_RUNTIME_ID}"

    aws bedrock-agentcore-control update-agent-runtime \
        --agent-runtime-id "${AGENT_RUNTIME_ID}" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-runtime-role" \
        --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
        --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
        ${AUTH_ARGS} \
        --region ${AWS_REGION} \
        --no-cli-pager

    echo -n "Waiting for runtime"
    while [ "$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "${AGENT_RUNTIME_ID}" --region ${AWS_REGION} \
        --no-cli-pager --query 'status' --output text)" != "READY" ]; do
        echo -n "."; sleep 5
    done && echo " READY"
else
    echo "Creating AgentCore Runtime: ${RUNTIME_NAME}"

    AGENT_RUNTIME_ID=$(aws bedrock-agentcore-control create-agent-runtime \
        --agent-runtime-name "${RUNTIME_NAME}" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-runtime-role" \
        --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
        --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
        ${AUTH_ARGS} \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'agentRuntimeId' --output text)

    echo -n "Waiting for runtime"
    while [ "$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "${AGENT_RUNTIME_ID}" --region ${AWS_REGION} \
        --no-cli-pager --query 'status' --output text)" != "READY" ]; do
        echo -n "."; sleep 5
    done && echo " READY"
fi

# Save runtime ID to environment
RUNTIME_ID_VAR="${VAR_PREFIX}_RUNTIME_ID"
if ! grep -q "${RUNTIME_ID_VAR}=${AGENT_RUNTIME_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak "/${RUNTIME_ID_VAR}=/d" ~/environment/.envrc 2>/dev/null || true
    echo "export ${RUNTIME_ID_VAR}=${AGENT_RUNTIME_ID}" >> ~/environment/.envrc
fi

## Saving endpoint

echo ""
echo "6. Save endpoint"

RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${AGENT_RUNTIME_ID}"
AGENT_ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)/invocations?qualifier=DEFAULT"

RUNTIME_ARN_VAR="${VAR_PREFIX}_RUNTIME_ARN"
sed -i.bak "/${RUNTIME_ARN_VAR}=/d" ~/environment/.envrc 2>/dev/null || true
echo "export ${RUNTIME_ARN_VAR}=${RUNTIME_ARN}" >> ~/environment/.envrc

ENDPOINT_VAR="${VAR_PREFIX}_ENDPOINT"
sed -i.bak "/${ENDPOINT_VAR}=/d" ~/environment/.envrc 2>/dev/null || true
echo "export ${ENDPOINT_VAR}=${AGENT_ENDPOINT}" >> ~/environment/.envrc

rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "AI Agent Runtime deployment complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  ${RUNTIME_ID_VAR}=${AGENT_RUNTIME_ID}"
echo "  ${RUNTIME_ARN_VAR}=${RUNTIME_ARN}"
echo "  ${ENDPOINT_VAR}=${AGENT_ENDPOINT}"
