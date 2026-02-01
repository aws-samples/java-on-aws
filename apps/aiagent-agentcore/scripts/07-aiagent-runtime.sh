#!/bin/bash
# ============================================================
# 07-aiagent-runtime.sh - Deploy AI Agent to AgentCore Runtime
# ============================================================
# Wires Memory, KB, and Cognito if they exist
# Idempotent - safe to run multiple times
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
RUNTIME_NAME="${APP_NAME}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)

ECR_REPO="${APP_NAME}"
RUNTIME_ROLE="${APP_NAME}-runtime-role"
COGNITO_POOL="${APP_NAME}-user-pool"
MEMORY_NAME="${APP_NAME}_memory"
KB_NAME="${APP_NAME}-kb"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../aiagent"

echo "🚀 Deploying AgentCore Runtime"
echo ""
echo "Region: ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo ""

# ============================================================
# 1. ECR Repository
# ============================================================
echo "1️⃣  Creating ECR repository: ${ECR_REPO}"
aws ecr create-repository \
  --repository-name "${ECR_REPO}" \
  --region "${REGION}" \
  --no-cli-pager 2>/dev/null || echo "   ✓ Repository already exists"

# ============================================================
# 2. IAM Role
# ============================================================
echo ""
echo "2️⃣  Checking IAM role: ${RUNTIME_ROLE}"

# Check if workshop boundary exists
BOUNDARY_ARN=""
if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" --no-cli-pager >/dev/null 2>&1; then
  BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary"
fi

if aws iam get-role --role-name "${RUNTIME_ROLE}" --no-cli-pager >/dev/null 2>&1; then
  echo "   ✓ Role exists"
else
  echo "   Creating role..."
  aws iam create-role \
    --role-name "${RUNTIME_ROLE}" \
    ${BOUNDARY_ARN:+--permissions-boundary "${BOUNDARY_ARN}"} \
    --assume-role-policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Principal\": {\"Service\": \"bedrock-agentcore.amazonaws.com\"},
        \"Action\": \"sts:AssumeRole\",
        \"Condition\": {
          \"StringEquals\": {\"aws:SourceAccount\": \"${ACCOUNT_ID}\"},
          \"ArnLike\": {\"aws:SourceArn\": \"arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:*\"}
        }
      }]
    }" \
    --description "Role for AI Agent AgentCore Runtime" \
    --no-cli-pager >/dev/null

  aws iam put-role-policy \
    --role-name "${RUNTIME_ROLE}" \
    --policy-name "AgentCoreExecutionPolicy" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"bedrock:*\", \"bedrock-agentcore:*\"],
          \"Resource\": \"*\"
        },
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"ecr:*\", \"logs:*\", \"xray:*\", \"cloudwatch:*\"],
          \"Resource\": \"*\"
        },
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"aws-marketplace:Subscribe\", \"aws-marketplace:Unsubscribe\", \"aws-marketplace:ViewSubscriptions\"],
          \"Resource\": \"*\"
        }
      ]
    }" \
    --no-cli-pager
  echo "   ✓ Role created"
fi

# ============================================================
# 3. Find Cognito User Pool
# ============================================================
echo ""
echo "3️⃣  Finding Cognito User Pool..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "${REGION}" --no-cli-pager \
  --query "UserPools[?Name=='${COGNITO_POOL}'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -z "${USER_POOL_ID}" ] || [ "${USER_POOL_ID}" = "None" ] || [ "${USER_POOL_ID}" = "null" ]; then
  echo "   ❌ Cognito User Pool not found. Run ./03-cognito.sh first"
  exit 1
fi
echo "   ✓ Found User Pool: ${USER_POOL_ID}"

CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
  --user-pool-id "${USER_POOL_ID}" \
  --region "${REGION}" \
  --no-cli-pager \
  --query "UserPoolClients[?ClientName=='${APP_NAME}-client'].ClientId | [0]" \
  --output text 2>/dev/null || echo "")

if [ -z "${CLIENT_ID}" ] || [ "${CLIENT_ID}" = "None" ] || [ "${CLIENT_ID}" = "null" ]; then
  echo "   ❌ Cognito App Client not found"
  exit 1
fi
echo "   ✓ Found Client: ${CLIENT_ID}"

# ============================================================
# 4. Build and Push Container Image
# ============================================================
echo ""
echo "4️⃣  Building and pushing container image with Spring Boot Buildpacks..."
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
ECR_URI="${ECR_REGISTRY}/${ECR_REPO}"

# Login to ECR
aws ecr get-login-password --region "${REGION}" --no-cli-pager | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

cd "${PROJECT_DIR}"
mvn -ntp spring-boot:build-image \
  -DskipTests \
  -Dspring-boot.build-image.imageName="${ECR_URI}:latest" \
  -Dspring-boot.build-image.imagePlatform=linux/arm64

docker push "${ECR_URI}:latest"

echo "   ✓ Image built and pushed: ${ECR_URI}:latest"

# ============================================================
# 5. Lookup Memory and KB
# ============================================================
echo ""
echo "5️⃣  Looking up Memory and KB..."

MEMORY_ID=$(aws bedrock-agentcore-control list-memories --region "${REGION}" --no-cli-pager \
  --query "memories[?starts_with(id, '${MEMORY_NAME}')].id | [0]" --output text 2>/dev/null || echo "")
if [ -n "${MEMORY_ID}" ] && [ "${MEMORY_ID}" != "None" ] && [ "${MEMORY_ID}" != "null" ]; then
  echo "   ✓ Found Memory: ${MEMORY_ID}"

  SEMANTIC_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='SemanticFacts'].strategyId | [0]" --output text 2>/dev/null || echo "")
  PREFS_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='UserPreferences'].strategyId | [0]" --output text 2>/dev/null || echo "")
  SUMMARY_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='ConversationSummary'].strategyId | [0]" --output text 2>/dev/null || echo "")
  EPISODIC_ID=$(aws bedrock-agentcore-control get-memory --region "${REGION}" --memory-id "${MEMORY_ID}" --no-cli-pager \
    --query "memory.strategies[?name=='EpisodicMemory'].strategyId | [0]" --output text 2>/dev/null || echo "")
else
  echo "   ⚠️  Memory not found"
  MEMORY_ID=""
fi

KB_ID=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
  --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null || echo "")
if [ -n "${KB_ID}" ] && [ "${KB_ID}" != "None" ] && [ "${KB_ID}" != "null" ]; then
  echo "   ✓ Found KB: ${KB_ID}"
else
  echo "   ⚠️  KB not found"
  KB_ID=""
fi

# Build environment variables
ENV_VARS='{}'
if [ -n "${MEMORY_ID}" ]; then
  HAS_LTM="false"
  [ -n "${SEMANTIC_ID}" ] && [ "${SEMANTIC_ID}" != "None" ] && HAS_LTM="true"
  [ -n "${PREFS_ID}" ] && [ "${PREFS_ID}" != "None" ] && HAS_LTM="true"
  [ -n "${SUMMARY_ID}" ] && [ "${SUMMARY_ID}" != "None" ] && HAS_LTM="true"
  [ -n "${EPISODIC_ID}" ] && [ "${EPISODIC_ID}" != "None" ] && HAS_LTM="true"

  ENV_VARS=$(echo "${ENV_VARS}" | jq \
    --arg m "${MEMORY_ID}" \
    --arg s "${SEMANTIC_ID:-}" \
    --arg p "${PREFS_ID:-}" \
    --arg su "${SUMMARY_ID:-}" \
    --arg e "${EPISODIC_ID:-}" \
    '. + {
      AGENTCORE_MEMORY_MEMORY_ID: $m,
      AGENTCORE_MEMORY_LONG_TERM_SEMANTIC_STRATEGY_ID: $s,
      AGENTCORE_MEMORY_LONG_TERM_USER_PREFERENCE_STRATEGY_ID: $p,
      AGENTCORE_MEMORY_LONG_TERM_SUMMARY_STRATEGY_ID: $su,
      AGENTCORE_MEMORY_LONG_TERM_EPISODIC_STRATEGY_ID: $e
    }')
fi
if [ -n "${KB_ID}" ]; then
  ENV_VARS=$(echo "${ENV_VARS}" | jq --arg k "${KB_ID}" '. + {SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID: $k}')
fi

# ============================================================
# 6. Ensure VPC exists
# ============================================================
echo ""
echo "6️⃣  Checking VPC..."

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=workshop-vpc" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -z "${VPC_ID}" ] || [ "${VPC_ID}" = "None" ] || [ "${VPC_ID}" = "null" ]; then
  echo "   VPC not found, creating..."
  "${SCRIPT_DIR}/09-vpc.sh"
  VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=workshop-vpc" \
    --query 'Vpcs[0].VpcId' --output text --no-cli-pager)
fi
echo "   ✓ VPC: ${VPC_ID}"

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=tag:aws-cdk:subnet-type,Values=Private" \
            "Name=availability-zone-id,Values=use1-az1,use1-az2,use1-az4" \
  --query 'Subnets[*].SubnetId' --output json --no-cli-pager)
echo "   ✓ Subnets: ${SUBNET_IDS}"

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=workshop-sg" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)
echo "   ✓ Security Group: ${SG_ID}"

# ============================================================
# 7. Create/Update AgentCore Runtime
# ============================================================
echo ""
echo "7️⃣  Creating AgentCore Runtime: ${RUNTIME_NAME}"
RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes --region "${REGION}" --no-cli-pager \
  --query "agentRuntimes[?agentRuntimeName=='${RUNTIME_NAME}'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "")

COGNITO_DISCOVERY="https://cognito-idp.${REGION}.amazonaws.com/${USER_POOL_ID}/.well-known/openid-configuration"
AUTHORIZER_CONFIG="{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${COGNITO_DISCOVERY}\",\"allowedClients\":[\"${CLIENT_ID}\"]}}"

NETWORK_CONFIG=$(jq -n \
  --argjson subnets "${SUBNET_IDS}" \
  --arg sg "${SG_ID}" \
  '{networkMode: "VPC", networkModeConfig: {subnets: $subnets, securityGroups: [$sg]}}')

if [ -n "${RUNTIME_ID}" ] && [ "${RUNTIME_ID}" != "None" ] && [ "${RUNTIME_ID}" != "null" ]; then
  echo "   ✓ Runtime already exists: ${RUNTIME_ID}"
  echo "   Updating runtime..."

  aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-id "${RUNTIME_ID}" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${RUNTIME_ROLE}" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:latest\"}}" \
    --network-configuration "${NETWORK_CONFIG}" \
    --environment-variables "${ENV_VARS}" \
    --authorizer-configuration "${AUTHORIZER_CONFIG}" \
    --request-header-configuration '{"requestHeaderAllowlist":["Authorization"]}' \
    --region "${REGION}" \
    --no-cli-pager >/dev/null
else
  RUNTIME_RESPONSE=$(aws bedrock-agentcore-control create-agent-runtime \
    --agent-runtime-name "${RUNTIME_NAME}" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${RUNTIME_ROLE}" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:latest\"}}" \
    --network-configuration "${NETWORK_CONFIG}" \
    --environment-variables "${ENV_VARS}" \
    --authorizer-configuration "${AUTHORIZER_CONFIG}" \
    --request-header-configuration '{"requestHeaderAllowlist":["Authorization"]}' \
    --region "${REGION}" \
    --no-cli-pager)

  RUNTIME_ID=$(echo "${RUNTIME_RESPONSE}" | jq -r '.agentRuntimeId')
  echo "   ✓ Created Runtime: ${RUNTIME_ID}"
fi

echo "   Waiting for runtime to be READY..."
for i in {1..90}; do
  STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${RUNTIME_ID}" \
    --region "${REGION}" \
    --query 'status' --output text \
    --no-cli-pager 2>/dev/null || echo "UNKNOWN")

  if [ "${STATUS}" = "READY" ]; then
    echo "   ✓ Runtime is READY"
    break
  fi

  if [ "${STATUS}" = "FAILED" ] || [ "${STATUS}" = "CREATE_FAILED" ] || [ "${STATUS}" = "UPDATE_FAILED" ]; then
    echo "   ❌ Runtime failed: ${STATUS}"
    exit 1
  fi

  if [ $((i % 15)) -eq 0 ]; then
    echo "   ⏳ Status: ${STATUS}"
  fi
  sleep 2
done

RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"

echo ""
echo "✅ AgentCore Deployment Complete"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 Runtime ID: ${RUNTIME_ID}"
echo "🔗 Runtime ARN: ${RUNTIME_ARN}"
echo "👤 Cognito Pool: ${USER_POOL_ID}"
echo "🔑 Client ID: ${CLIENT_ID}"
echo "💾 Memory: ${MEMORY_ID:-<not configured>}"
echo "📚 KB: ${KB_ID:-<not configured>}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
