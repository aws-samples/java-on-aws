#!/bin/bash
# ============================================================
# test-agent.sh - Test AgentCore Runtime with Cognito auth
# ============================================================
# Tests memory by asking name, then asking what the name is
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
RUNTIME_NAME="${APP_NAME}"
COGNITO_POOL="${APP_NAME}-user-pool"

USERNAME="bob"
PASSWORD="${IDE_PASSWORD:-Workshop123!}"

echo "🧪 Testing AgentCore Runtime"
echo ""
echo "Region: ${REGION}"
echo "User: ${USERNAME}"
echo ""

# 1. Find Cognito
echo "1️⃣  Finding Cognito configuration..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "${REGION}" --no-cli-pager \
  --query "UserPools[?Name=='${COGNITO_POOL}'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -z "${USER_POOL_ID}" ] || [ "${USER_POOL_ID}" = "None" ] || [ "${USER_POOL_ID}" = "null" ]; then
  echo "   ❌ Cognito User Pool not found"
  exit 1
fi
echo "   ✓ User Pool: ${USER_POOL_ID}"

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
echo "   ✓ Client ID: ${CLIENT_ID}"

# 2. Find Runtime
echo ""
echo "2️⃣  Finding AgentCore Runtime..."
RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes --region "${REGION}" --no-cli-pager \
  --query "agentRuntimes[?agentRuntimeName=='${RUNTIME_NAME}'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "")

if [ -z "${RUNTIME_ID}" ] || [ "${RUNTIME_ID}" = "None" ] || [ "${RUNTIME_ID}" = "null" ]; then
  echo "   ❌ AgentCore Runtime not found"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"
RUNTIME_ARN_ENCODED=$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)
API_ENDPOINT="https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/${RUNTIME_ARN_ENCODED}/invocations?qualifier=DEFAULT"
echo "   ✓ Runtime ID: ${RUNTIME_ID}"

# 3. Authenticate
echo ""
echo "3️⃣  Authenticating as ${USERNAME}..."
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id "${CLIENT_ID}" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=${USERNAME},PASSWORD=${PASSWORD}" \
  --region "${REGION}" \
  --no-cli-pager \
  --query 'AuthenticationResult.AccessToken' --output text 2>/dev/null || echo "")

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "None" ] || [ "${TOKEN}" = "null" ]; then
  echo "   ❌ Authentication failed"
  exit 1
fi
echo "   ✓ Authenticated"

# 4. First message
echo ""
echo "4️⃣  Sending first message..."
echo "   📤 \"My name is Bob, who are you?\""
echo ""
echo "   📥 Response:"
echo "   -----------------------------------------"

curl -N -s -X POST "${API_ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"prompt":"My name is Bob, who are you?"}' | sed 's/^data://g' | tr -d '\n'

echo ""
echo ""

# 5. Second message (test memory)
echo ""
echo "5️⃣  Sending second message (testing memory)..."
echo "   📤 \"What is my name?\""
echo ""
echo "   📥 Response:"
echo "   -----------------------------------------"

RESPONSE2=$(curl -N -s -X POST "${API_ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"prompt":"What is my name?"}')

echo "${RESPONSE2}" | sed 's/^data://g' | tr -d '\n'
echo ""

# Check memory result
echo ""
if echo "${RESPONSE2}" | grep -qi "bob"; then
  echo "✅ Memory test PASSED - Agent remembered 'Bob'"
else
  echo "⚠️  Memory test UNCLEAR - Check response"
fi

# 6. Weather test (tests internet connectivity)
echo ""
echo "6️⃣  Sending weather question (testing internet access)..."
echo "   📤 \"What is the weather tomorrow in Las Vegas?\""
echo ""
echo "   📥 Response:"
echo "   -----------------------------------------"

RESPONSE3=$(curl -N -s -X POST "${API_ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"prompt":"What is the weather tomorrow in Las Vegas?"}')

echo "${RESPONSE3}" | sed 's/^data://g' | tr -d '\n'
echo ""

# Check weather result
echo ""
if echo "${RESPONSE3}" | grep -qiE "(weather|temperature|degrees|°|forecast|las vegas)"; then
  echo "✅ Weather test PASSED - Agent retrieved weather data"
else
  echo "⚠️  Weather test UNCLEAR - Check response"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 All tests completed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
