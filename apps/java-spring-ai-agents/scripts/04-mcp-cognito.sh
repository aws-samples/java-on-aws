#!/bin/bash
set -e

echo "=============================================="
echo "04-mcp-cognito.sh - M2M Cognito Setup"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Creating ~/environment/.envrc"
    mkdir -p ~/environment
    touch ~/environment/.envrc
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

## Creating the M2M Cognito pool

echo ""
echo "## Creating M2M authentication"
echo "1. Create a dedicated Cognito User Pool for M2M authentication"

# Check if pool already exists
EXISTING_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
    --query "UserPools[?Name=='mcp-gateway-pool'].Id | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_POOL_ID}" != "None" ] && [ -n "${EXISTING_POOL_ID}" ]; then
    echo "Cognito User Pool already exists: ${EXISTING_POOL_ID}"
    GATEWAY_POOL_ID="${EXISTING_POOL_ID}"
else
    echo "Creating Cognito User Pool: mcp-gateway-pool"
    GATEWAY_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "mcp-gateway-pool" \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'UserPool.Id' --output text)
fi

# Save to environment
if ! grep -q "GATEWAY_POOL_ID=${GATEWAY_POOL_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/GATEWAY_POOL_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export GATEWAY_POOL_ID=${GATEWAY_POOL_ID}" >> ~/environment/.envrc
fi

## Creating the resource server

echo ""
echo "2. Create the resource server"

# Check if resource server exists
EXISTING_RS=$(aws cognito-idp describe-resource-server \
    --user-pool-id "${GATEWAY_POOL_ID}" \
    --identifier "gateway" \
    --region ${AWS_REGION} \
    --no-cli-pager 2>/dev/null || echo "")

if [ -n "${EXISTING_RS}" ]; then
    echo "Resource server already exists: gateway"
else
    echo "Creating resource server: gateway"
    aws cognito-idp create-resource-server \
        --user-pool-id "${GATEWAY_POOL_ID}" \
        --identifier "gateway" \
        --name "Gateway API" \
        --scopes '[{"ScopeName":"invoke","ScopeDescription":"Invoke gateway tools"}]' \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Creating the Cognito domain

echo ""
echo "3. Create the Cognito domain"

# Check if domain exists
EXISTING_DOMAIN=$(aws cognito-idp describe-user-pool \
    --user-pool-id "${GATEWAY_POOL_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query 'UserPool.Domain' --output text 2>/dev/null || echo "None")

if [ "${EXISTING_DOMAIN}" != "None" ] && [ -n "${EXISTING_DOMAIN}" ]; then
    echo "Cognito domain already exists: ${EXISTING_DOMAIN}"
else
    echo "Creating Cognito domain: mcp-gateway-${ACCOUNT_ID}"
    aws cognito-idp create-user-pool-domain \
        --domain "mcp-gateway-${ACCOUNT_ID}" \
        --user-pool-id "${GATEWAY_POOL_ID}" \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Creating the app client

echo ""
echo "4. Create the app client"

# Check if client exists
EXISTING_CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
    --user-pool-id "${GATEWAY_POOL_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query "UserPoolClients[?ClientName=='mcp-gateway-client'].ClientId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_CLIENT_ID}" != "None" ] && [ -n "${EXISTING_CLIENT_ID}" ]; then
    echo "App client already exists: ${EXISTING_CLIENT_ID}"
    GATEWAY_CLIENT_ID="${EXISTING_CLIENT_ID}"
else
    echo "Creating app client: mcp-gateway-client"
    GATEWAY_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "${GATEWAY_POOL_ID}" \
        --client-name "mcp-gateway-client" \
        --generate-secret \
        --allowed-o-auth-flows "client_credentials" \
        --allowed-o-auth-scopes "gateway/invoke" \
        --allowed-o-auth-flows-user-pool-client \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'UserPoolClient.ClientId' --output text)
fi

GATEWAY_DISCOVERY_URL="https://cognito-idp.${AWS_REGION}.amazonaws.com/${GATEWAY_POOL_ID}/.well-known/openid-configuration"

# Save to environment
if ! grep -q "GATEWAY_CLIENT_ID=${GATEWAY_CLIENT_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/GATEWAY_CLIENT_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export GATEWAY_CLIENT_ID=${GATEWAY_CLIENT_ID}" >> ~/environment/.envrc
fi

if ! grep -q "GATEWAY_DISCOVERY_URL=" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/GATEWAY_DISCOVERY_URL=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export GATEWAY_DISCOVERY_URL=${GATEWAY_DISCOVERY_URL}" >> ~/environment/.envrc
fi

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "M2M Cognito setup complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  GATEWAY_POOL_ID=${GATEWAY_POOL_ID}"
echo "  GATEWAY_CLIENT_ID=${GATEWAY_CLIENT_ID}"
echo "  GATEWAY_DISCOVERY_URL=${GATEWAY_DISCOVERY_URL}"
