#!/bin/bash
set -e

echo "=============================================="
echo "20-test.sh - Test AI Agent Runtime"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run deployment scripts first."
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
AWS_REGION=$(aws configure get region --no-cli-pager)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

## Check runtime status

echo ""
echo "## Checking runtime status"

RUNTIME_STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${AIAGENT_RUNTIME_ID}" \
    --region ${AWS_REGION} \
    --no-cli-pager \
    --query 'status' --output text)

echo "Runtime status: ${RUNTIME_STATUS}"

if [ "${RUNTIME_STATUS}" != "READY" ]; then
    echo "Error: Runtime is not READY"
    exit 1
fi

## Get access token

echo ""
echo "## Getting access token"

TOKEN_RESPONSE=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id "${AIAGENT_CLIENT_ID}" \
    --auth-parameters "USERNAME=user,PASSWORD=${IDE_PASSWORD}" \
    --region ${AWS_REGION} \
    --no-cli-pager 2>/dev/null || echo "")

if [ -z "${TOKEN_RESPONSE}" ]; then
    echo "Warning: Could not get token. Skipping API test."
else
    ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.AuthenticationResult.AccessToken')

    ## Test the agent API

    echo ""
    echo "## Testing agent API"

    RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${AIAGENT_RUNTIME_ID}"
    ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)/invocations?qualifier=DEFAULT"

    TEST_PAYLOAD='{"conversationId":"test-'$(date +%s)'","message":"Hi, how can you help me?"}'

    echo "Sending test message: Hi, how can you help me?"

    RESPONSE=$(curl -s -X POST "${ENDPOINT}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${TEST_PAYLOAD}" 2>/dev/null || echo "")

    if [ -n "${RESPONSE}" ]; then
        echo ""
        echo "Response received:"
        echo "${RESPONSE}" | jq -r '.message // .error // .' 2>/dev/null | head -20 || echo "${RESPONSE}" | head -500
    else
        echo "Warning: No response from agent API"
    fi
fi

## Get recent logs

echo ""
echo "## Recent logs (last 20 lines)"

LOG_GROUP="/aws/bedrock-agentcore/runtimes/${AIAGENT_RUNTIME_ID}"

# Get the most recent log stream
LOG_STREAM=$(aws logs describe-log-streams \
    --log-group-name "${LOG_GROUP}" \
    --order-by LastEventTime \
    --descending \
    --limit 1 \
    --region ${AWS_REGION} \
    --no-cli-pager \
    --query 'logStreams[0].logStreamName' --output text 2>/dev/null || echo "None")

if [ "${LOG_STREAM}" != "None" ] && [ -n "${LOG_STREAM}" ]; then
    aws logs get-log-events \
        --log-group-name "${LOG_GROUP}" \
        --log-stream-name "${LOG_STREAM}" \
        --limit 20 \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'events[].message' --output text 2>/dev/null | tail -20 || echo "Could not fetch logs"
else
    echo "No log streams found for ${LOG_GROUP}"
fi

## Show access information

echo ""
echo "=============================================="
echo "AI Agent Access Information"
echo "=============================================="
echo ""
echo "CloudFront URL: https://${UI_DOMAIN}"
echo "Password: ${IDE_PASSWORD}"
echo ""
echo "Runtime ID: ${AIAGENT_RUNTIME_ID}"
echo "Runtime Status: ${RUNTIME_STATUS}"
