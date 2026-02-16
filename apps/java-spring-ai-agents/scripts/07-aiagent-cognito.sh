#!/bin/bash
set -e

echo "=============================================="
echo "07-aiagent-cognito.sh - AI Agent Cognito Setup"
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

## Creating the Cognito User Pool

echo ""
echo "## Creating user authentication"
echo "1. Create an Amazon Cognito User Pool"

# Check if pool already exists
EXISTING_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
    --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_POOL_ID}" != "None" ] && [ -n "${EXISTING_POOL_ID}" ]; then
    echo "Cognito User Pool already exists: ${EXISTING_POOL_ID}"
    AIAGENT_USER_POOL_ID="${EXISTING_POOL_ID}"
else
    echo "Creating Cognito User Pool: aiagent-user-pool"
    AIAGENT_USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "aiagent-user-pool" \
        --policies '{
            "PasswordPolicy": {
                "MinimumLength": 8,
                "RequireUppercase": true,
                "RequireLowercase": true,
                "RequireNumbers": true,
                "RequireSymbols": false
            }
        }' \
        --auto-verified-attributes email \
        --username-configuration '{"CaseSensitive": false}' \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'UserPool.Id' --output text)
fi

# Save to environment
if ! grep -q "AIAGENT_USER_POOL_ID=${AIAGENT_USER_POOL_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/AIAGENT_USER_POOL_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export AIAGENT_USER_POOL_ID=${AIAGENT_USER_POOL_ID}" >> ~/environment/.envrc
fi

AIAGENT_DISCOVERY_URL="https://cognito-idp.${AWS_REGION}.amazonaws.com/${AIAGENT_USER_POOL_ID}/.well-known/openid-configuration"
if ! grep -q "AIAGENT_DISCOVERY_URL=" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/AIAGENT_DISCOVERY_URL=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export AIAGENT_DISCOVERY_URL=${AIAGENT_DISCOVERY_URL}" >> ~/environment/.envrc
fi

## Creating the app client

echo ""
echo "2. Create an app client for the AI agent"

# Check if client exists
EXISTING_CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
    --user-pool-id "${AIAGENT_USER_POOL_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query "UserPoolClients[?ClientName=='aiagent-client'].ClientId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_CLIENT_ID}" != "None" ] && [ -n "${EXISTING_CLIENT_ID}" ]; then
    echo "App client already exists: ${EXISTING_CLIENT_ID}"
    AIAGENT_CLIENT_ID="${EXISTING_CLIENT_ID}"
else
    echo "Creating app client: aiagent-client"
    AIAGENT_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "${AIAGENT_USER_POOL_ID}" \
        --client-name "aiagent-client" \
        --no-generate-secret \
        --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
        --region ${AWS_REGION} \
        --no-cli-pager \
        --query 'UserPoolClient.ClientId' --output text)
fi

# Save to environment
if ! grep -q "AIAGENT_CLIENT_ID=${AIAGENT_CLIENT_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/AIAGENT_CLIENT_ID=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export AIAGENT_CLIENT_ID=${AIAGENT_CLIENT_ID}" >> ~/environment/.envrc
fi

## Creating test users

echo ""
echo "3. Create test users"

# Check if IDE_PASSWORD is set
if [ -z "${IDE_PASSWORD}" ]; then
    echo "Warning: IDE_PASSWORD not set. Using default password 'Workshop123'"
    IDE_PASSWORD="Workshop123"
fi

for USER in admin alice bob; do
    # Check if user exists
    USER_EXISTS=$(aws cognito-idp admin-get-user \
        --user-pool-id "${AIAGENT_USER_POOL_ID}" \
        --username "${USER}" \
        --region ${AWS_REGION} \
        --no-cli-pager 2>/dev/null || echo "")

    if [ -n "${USER_EXISTS}" ]; then
        echo "User already exists: ${USER}"
    else
        echo "Creating user: ${USER}"
        aws cognito-idp admin-create-user \
            --user-pool-id "${AIAGENT_USER_POOL_ID}" \
            --username "${USER}" \
            --temporary-password "${IDE_PASSWORD}" \
            --message-action SUPPRESS \
            --region ${AWS_REGION} \
            --no-cli-pager

        aws cognito-idp admin-set-user-password \
            --user-pool-id "${AIAGENT_USER_POOL_ID}" \
            --username "${USER}" \
            --password "${IDE_PASSWORD}" \
            --permanent \
            --region ${AWS_REGION} \
            --no-cli-pager
    fi
done

echo "Test users: admin, alice, bob"

## Save issuer URI for Spring Security

echo ""
echo "4. Save issuer URI for Spring Security"

SPRING_ISSUER_URI="https://cognito-idp.${AWS_REGION}.amazonaws.com/${AIAGENT_USER_POOL_ID}"
if ! grep -q "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI=" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI=${SPRING_ISSUER_URI}" >> ~/environment/.envrc
fi

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "AI Agent Cognito setup complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  AIAGENT_USER_POOL_ID=${AIAGENT_USER_POOL_ID}"
echo "  AIAGENT_CLIENT_ID=${AIAGENT_CLIENT_ID}"
echo "  AIAGENT_DISCOVERY_URL=${AIAGENT_DISCOVERY_URL}"
echo ""
echo "Test users created: admin, alice, bob (password: \${IDE_PASSWORD})"
