#!/bin/bash
set -e

echo "=============================================="
echo "06-mcp-gateway.sh - AgentCore Gateway Setup"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${GATEWAY_POOL_ID}" ] || [ -z "${GATEWAY_CLIENT_ID}" ] || [ -z "${MCP_RUNTIME_ID}" ]; then
    echo "Error: Missing required environment variables. Run 04-mcp-cognito.sh and 05-mcp-runtime.sh first."
    exit 1
fi

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

## Creating the Gateway IAM role

echo ""
echo "## Creating the Gateway"
echo "1. Create the Gateway IAM role"

# Check if role exists
if aws iam get-role --role-name "mcp-gateway-role" --no-cli-pager >/dev/null 2>&1; then
    echo "IAM role already exists: mcp-gateway-role"
else
    echo "Creating IAM role: mcp-gateway-role"

    cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "bedrock-agentcore.amazonaws.com"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"}
    }
  }]
}
EOF

    aws iam create-role \
        --role-name "mcp-gateway-role" \
        --permissions-boundary "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --no-cli-pager

    cat > /tmp/gateway-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["bedrock-agentcore:InvokeAgentRuntime"],
      "Resource": "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:GetWorkloadAccessToken",
        "bedrock-agentcore:GetResourceApiKey",
        "bedrock-agentcore:GetResourceOauth2Token"
      ],
      "Resource": [
        "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:workload-identity-directory/*",
        "arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:token-vault/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:bedrock-agentcore-identity!*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "mcp-gateway-role" \
        --policy-name "GatewayPolicy" \
        --policy-document file:///tmp/gateway-policy.json \
        --no-cli-pager

    rm -f /tmp/trust-policy.json /tmp/gateway-policy.json
fi

## Creating the Gateway

echo ""
echo "2. Create the Gateway"

# Check if gateway already exists
EXISTING_GATEWAY_ID=$(aws bedrock-agentcore-control list-gateways \
    --region ${AWS_REGION} --no-cli-pager \
    --query "items[?name=='mcp-gateway'].gatewayId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_GATEWAY_ID}" != "None" ] && [ -n "${EXISTING_GATEWAY_ID}" ]; then
    echo "Gateway already exists: ${EXISTING_GATEWAY_ID}"
    GATEWAY_ID="${EXISTING_GATEWAY_ID}"
else
    echo "Creating Gateway: mcp-gateway"

    GATEWAY_ID=$(aws bedrock-agentcore-control create-gateway \
        --name "mcp-gateway" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/mcp-gateway-role" \
        --protocol-type "MCP" \
        --protocol-configuration '{"mcp":{"searchType":"SEMANTIC"}}' \
        --authorizer-type "AWS_IAM" \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'gatewayId' --output text)

    echo -n "Waiting for gateway"
    while [ "$(aws bedrock-agentcore-control get-gateway \
        --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} \
        --no-cli-pager --query 'status' --output text)" != "READY" ]; do
        echo -n "."; sleep 5
    done && echo " READY"
fi

# Save gateway ID to environment
if ! grep -q "GATEWAY_ID=${GATEWAY_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/GATEWAY_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export GATEWAY_ID=${GATEWAY_ID}" >> ~/environment/.envrc
fi

GATEWAY_URL=$(aws bedrock-agentcore-control get-gateway \
    --gateway-identifier "${GATEWAY_ID}" \
    --region ${AWS_REGION} \
    --no-cli-pager --query 'gatewayUrl' --output text)

if ! grep -q "GATEWAY_URL=" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/GATEWAY_URL=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export GATEWAY_URL=${GATEWAY_URL}" >> ~/environment/.envrc
fi

## Adding the backoffice target

echo ""
echo "3. Add the backoffice target"

# Check if OAuth provider exists
EXISTING_OAUTH_ARN=$(aws bedrock-agentcore-control list-oauth2-credential-providers \
    --region ${AWS_REGION} --no-cli-pager \
    --query "credentialProviders[?name=='mcp-backoffice-oauth'].credentialProviderArn | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_OAUTH_ARN}" != "None" ] && [ -n "${EXISTING_OAUTH_ARN}" ]; then
    echo "OAuth credential provider already exists"
    OAUTH_PROVIDER_ARN="${EXISTING_OAUTH_ARN}"
else
    echo "Creating OAuth credential provider"

    GATEWAY_CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client \
        --user-pool-id "${GATEWAY_POOL_ID}" --client-id "${GATEWAY_CLIENT_ID}" \
        --region ${AWS_REGION} --no-cli-pager \
        --query 'UserPoolClient.ClientSecret' --output text)

    OAUTH_CONFIG=$(jq -n \
        --arg clientId "${GATEWAY_CLIENT_ID}" \
        --arg clientSecret "${GATEWAY_CLIENT_SECRET}" \
        --arg discoveryUrl "${GATEWAY_DISCOVERY_URL}" \
        '{customOauth2ProviderConfig: {clientId: $clientId, clientSecret: $clientSecret, oauthDiscovery: {discoveryUrl: $discoveryUrl}}}')

    aws bedrock-agentcore-control create-oauth2-credential-provider \
        --name "mcp-backoffice-oauth" \
        --credential-provider-vendor "CustomOauth2" \
        --oauth2-provider-config-input "${OAUTH_CONFIG}" \
        --region ${AWS_REGION} \
        --no-cli-pager

    OAUTH_PROVIDER_ARN=$(aws bedrock-agentcore-control list-oauth2-credential-providers \
        --region ${AWS_REGION} --no-cli-pager \
        --query "credentialProviders[?name=='mcp-backoffice-oauth'].credentialProviderArn | [0]" --output text)
fi

# Check if backoffice target exists
EXISTING_BACKOFFICE_TARGET=$(aws bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
    --query "items[?name=='backoffice'].targetId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_BACKOFFICE_TARGET}" != "None" ] && [ -n "${EXISTING_BACKOFFICE_TARGET}" ]; then
    echo "Backoffice target already exists"
else
    echo "Creating backoffice target"

    RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${MCP_RUNTIME_ID}"
    MCP_ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)/invocations?qualifier=DEFAULT"
    TARGET_CONFIG=$(jq -n --arg endpoint "${MCP_ENDPOINT}" '{mcp: {mcpServer: {endpoint: $endpoint}}}')

    CREDENTIAL_CONFIG=$(jq -n --arg providerArn "${OAUTH_PROVIDER_ARN}" \
        '[{credentialProviderType: "OAUTH", credentialProvider: {oauthCredentialProvider: {providerArn: $providerArn, grantType: "CLIENT_CREDENTIALS", scopes: ["gateway/invoke"]}}}]')

    aws bedrock-agentcore-control create-gateway-target \
        --gateway-identifier "${GATEWAY_ID}" \
        --name "backoffice" \
        --target-configuration "${TARGET_CONFIG}" \
        --credential-provider-configurations "${CREDENTIAL_CONFIG}" \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Adding the holidays target

echo ""
echo "4. Add the holidays target"

# Check if API key provider exists
EXISTING_APIKEY_ARN=$(aws bedrock-agentcore-control list-api-key-credential-providers \
    --region ${AWS_REGION} --no-cli-pager \
    --query "credentialProviders[?name=='mcp-holidays-apikey-provider'].credentialProviderArn | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_APIKEY_ARN}" != "None" ] && [ -n "${EXISTING_APIKEY_ARN}" ]; then
    echo "API key credential provider already exists"
    APIKEY_PROVIDER_ARN="${EXISTING_APIKEY_ARN}"
else
    echo "Creating API key credential provider"

    aws bedrock-agentcore-control create-api-key-credential-provider \
        --name "mcp-holidays-apikey-provider" \
        --api-key "public-api-no-key-required" \
        --region ${AWS_REGION} \
        --no-cli-pager

    APIKEY_PROVIDER_ARN=$(aws bedrock-agentcore-control list-api-key-credential-providers \
        --region ${AWS_REGION} --no-cli-pager \
        --query "credentialProviders[?name=='mcp-holidays-apikey-provider'].credentialProviderArn | [0]" --output text)
fi

# Check if holidays target exists
EXISTING_HOLIDAYS_TARGET=$(aws bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
    --query "items[?name=='holidays'].targetId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_HOLIDAYS_TARGET}" != "None" ] && [ -n "${EXISTING_HOLIDAYS_TARGET}" ]; then
    echo "Holidays target already exists"
else
    echo "Creating holidays target"

    OPENAPI_SPEC=$(curl -s "https://date.nager.at/openapi/v3.json" | jq -c '
      .openapi = "3.0.0" |
      . + {servers: [{url: "https://date.nager.at"}]} |
      .paths |= with_entries(
        .value |= with_entries(
          .value.operationId = (.value.tags[0] // "api") + "_" + (.key | ascii_upcase) + "_" + (.value.summary | gsub("[^a-zA-Z0-9]"; "_") | .[0:30])
        )
      ) |
      walk(if type == "object" and .type == ["null", "string"] then .type = "string" | .nullable = true
           elif type == "object" and .type == ["null", "array"] then .type = "array" | .nullable = true
           elif type == "object" and .type == ["null", "integer"] then .type = "integer" | .nullable = true
           else . end)
    ')

    TARGET_CONFIG=$(jq -n --arg spec "${OPENAPI_SPEC}" \
        '{mcp: {openApiSchema: {inlinePayload: $spec}}}')

    CREDENTIAL_CONFIG=$(jq -n --arg providerArn "${APIKEY_PROVIDER_ARN}" \
        '[{credentialProviderType: "API_KEY", credentialProvider: {apiKeyCredentialProvider: {providerArn: $providerArn, credentialLocation: "HEADER", credentialParameterName: "X-Api-Key"}}}]')

    aws bedrock-agentcore-control create-gateway-target \
        --gateway-identifier "${GATEWAY_ID}" \
        --name "holidays" \
        --target-configuration "${TARGET_CONFIG}" \
        --credential-provider-configurations "${CREDENTIAL_CONFIG}" \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Waiting for targets to be ready

echo ""
echo "5. Wait for targets to be ready"

for TARGET_NAME in backoffice holidays; do
    TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
        --query "items[?name=='${TARGET_NAME}'].targetId | [0]" --output text)

    if [ -z "${TARGET_ID}" ] || [ "${TARGET_ID}" = "None" ]; then
        echo "Warning: ${TARGET_NAME} target not found, skipping"
        continue
    fi

    echo -n "Waiting for ${TARGET_NAME}"
    RETRY_COUNT=0
    MAX_RETRIES=60
    while true; do
        STATUS=$(aws bedrock-agentcore-control get-gateway-target \
            --gateway-identifier "${GATEWAY_ID}" --target-id "${TARGET_ID}" \
            --region ${AWS_REGION} --no-cli-pager \
            --query 'status' --output text 2>/dev/null || echo "ERROR")

        if [ "${STATUS}" = "READY" ]; then
            echo " READY"
            break
        elif [ "${STATUS}" = "FAILED" ] || [ "${STATUS}" = "ERROR" ]; then
            echo " ${STATUS}"
            echo "Error: ${TARGET_NAME} target failed. Check the MCP runtime logs."
            break
        fi

        echo -n "."
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ]; then
            echo " TIMEOUT (status: ${STATUS})"
            break
        fi
    done
done

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "Gateway setup complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  GATEWAY_ID=${GATEWAY_ID}"
echo "  GATEWAY_URL=${GATEWAY_URL}"
