#!/bin/bash

# Cognito - Create Amazon Cognito User Pool, client, and test users
# Based on: java-spring-ai-agents/content/security/index.en.md
# Note: This script only sets up Cognito infrastructure, does not modify the application

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

log_info "Setting up Amazon Cognito for AI Agent..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"

# Create User Pool
log_info "Creating Amazon Cognito User Pool..."
USER_POOL_ID=$(aws cognito-idp create-user-pool \
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
log_success "User Pool created: ${USER_POOL_ID}"

# Create app client
log_info "Creating app client..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)

CLIENT_ID=$(aws cognito-idp create-user-pool-client \
  --user-pool-id "${USER_POOL_ID}" \
  --client-name "aiagent-client" \
  --no-generate-secret \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --region ${AWS_REGION} \
  --no-cli-pager \
  --query 'UserPoolClient.ClientId' --output text)
log_success "App client created: ${CLIENT_ID}"

# Create test users
log_info "Creating test users (admin, alice, bob)..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)

for USER in admin alice bob; do
  aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${USER}" \
    --temporary-password "${IDE_PASSWORD}" \
    --message-action SUPPRESS \
    --region ${AWS_REGION} \
    --no-cli-pager

  aws cognito-idp admin-set-user-password \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${USER}" \
    --password "${IDE_PASSWORD}" \
    --permanent \
    --region ${AWS_REGION} \
    --no-cli-pager
done
log_success "Test users created: admin, alice, bob"

# Create config file for UI
log_info "Creating UI config file..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)
CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "${USER_POOL_ID}" --no-cli-pager \
  --query "UserPoolClients[?ClientName=='aiagent-client'].ClientId | [0]" --output text)

mkdir -p ~/environment/aiagent/src/main/resources/static
cat > ~/environment/aiagent/src/main/resources/static/config.json << EOF
{
  "userPoolId": "${USER_POOL_ID}",
  "clientId": "${CLIENT_ID}",
  "apiEndpoint": "invocations"
}
EOF
log_success "UI config file created"

# Output summary
log_info "Cognito configuration summary:"
echo "  User Pool ID: ${USER_POOL_ID}"
echo "  Client ID: ${CLIENT_ID}"
echo "  Issuer URI: https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
echo "  Test users: admin, alice, bob (password: \${IDE_PASSWORD})"

log_success "Amazon Cognito setup completed"
echo "✅ Success: Cognito User Pool and test users created"
echo "Test users: admin, alice, bob"
echo "Password: ${IDE_PASSWORD}"
