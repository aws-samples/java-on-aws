#!/bin/bash
# ============================================================
# 03-cognito.sh - Cognito Setup
# ============================================================
# Creates Cognito User Pool for AI Agent authentication
# Idempotent - safe to run multiple times
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"

echo "🔐 Creating Cognito Setup"
echo ""
echo "Region: ${REGION}"
echo ""

# ============================================================
# 1. Create Agent User Pool
# ============================================================
echo "1️⃣  Creating Agent User Pool: ${APP_NAME}-user-pool"
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "${REGION}" --no-cli-pager \
  --query "UserPools[?Name=='${APP_NAME}-user-pool'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "${USER_POOL_ID}" ] && [ "${USER_POOL_ID}" != "None" ] && [ "${USER_POOL_ID}" != "null" ]; then
  echo "   ✓ User Pool already exists: ${USER_POOL_ID}"
else
  USER_POOL_ID=$(aws cognito-idp create-user-pool \
    --pool-name "${APP_NAME}-user-pool" \
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
    --region "${REGION}" \
    --no-cli-pager \
    --query 'UserPool.Id' --output text)
  echo "   ✓ Created User Pool: ${USER_POOL_ID}"
fi

# ============================================================
# 2. Create Agent App Client
# ============================================================
echo ""
echo "2️⃣  Creating Agent App Client"
AGENT_CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
  --user-pool-id "${USER_POOL_ID}" \
  --region "${REGION}" \
  --no-cli-pager \
  --query "UserPoolClients[?ClientName=='${APP_NAME}-client'].ClientId | [0]" \
  --output text 2>/dev/null || echo "")

if [ -n "${AGENT_CLIENT_ID}" ] && [ "${AGENT_CLIENT_ID}" != "None" ] && [ "${AGENT_CLIENT_ID}" != "null" ]; then
  echo "   ✓ App Client already exists: ${AGENT_CLIENT_ID}"
else
  AGENT_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --user-pool-id "${USER_POOL_ID}" \
    --client-name "${APP_NAME}-client" \
    --no-generate-secret \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --region "${REGION}" \
    --no-cli-pager \
    --query 'UserPoolClient.ClientId' --output text)
  echo "   ✓ Created App Client: ${AGENT_CLIENT_ID}"
fi

# ============================================================
# 3. Create Test Users
# ============================================================
echo ""
echo "3️⃣  Creating test users"
TEST_PASSWORD="${IDE_PASSWORD:-Workshop123!}"
for USER in admin alice bob; do
  aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${USER}" \
    --temporary-password "${TEST_PASSWORD}" \
    --message-action SUPPRESS \
    --region "${REGION}" \
    --no-cli-pager 2>/dev/null || true

  aws cognito-idp admin-set-user-password \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${USER}" \
    --password "${TEST_PASSWORD}" \
    --permanent \
    --region "${REGION}" \
    --no-cli-pager 2>/dev/null || true
done
echo "   ✓ Test users: admin, alice, bob"

# ============================================================
# Summary
# ============================================================
echo ""
echo "✅ Cognito Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Agent User Pool: ${USER_POOL_ID}"
echo "Agent Client ID: ${AGENT_CLIENT_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Test users: admin, alice, bob (password: ${TEST_PASSWORD})"
