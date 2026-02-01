#!/bin/bash
# ============================================================
# 08-ui.sh - Deploy UI to S3 + CloudFront
# ============================================================
# Connects to AgentCore backend
# Idempotent - safe to run multiple times
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
RUNTIME_NAME="${APP_NAME}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)

COGNITO_POOL="${APP_NAME}-user-pool"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../aiagent"
UI_DIR="${PROJECT_DIR}/src/main/resources/static"

echo "🎨 Deploying UI"
echo ""
echo "Region: ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo ""

# ============================================================
# 1. Find Cognito User Pool
# ============================================================
echo "1️⃣  Finding Cognito User Pool..."
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
# 2. Find AgentCore Runtime
# ============================================================
echo ""
echo "2️⃣  Finding AgentCore Runtime..."
RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes --region "${REGION}" --no-cli-pager \
  --query "agentRuntimes[?agentRuntimeName=='${RUNTIME_NAME}'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "")

if [ -z "${RUNTIME_ID}" ] || [ "${RUNTIME_ID}" = "None" ] || [ "${RUNTIME_ID}" = "null" ]; then
  echo "   ❌ AgentCore Runtime not found. Run ./07-aiagent-runtime.sh first"
  exit 1
fi

RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"
RUNTIME_ARN_ENCODED=$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)
API_ENDPOINT="https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/${RUNTIME_ARN_ENCODED}/invocations?qualifier=DEFAULT"
echo "   ✓ Runtime ID: ${RUNTIME_ID}"

# ============================================================
# 3. Create or find S3 Bucket
# ============================================================
echo ""
echo "3️⃣  Setting up S3 bucket..."

EXISTING_BUCKET=$(aws s3api list-buckets --no-cli-pager \
  --query "Buckets[?starts_with(Name, '${APP_NAME}-ui-${ACCOUNT_ID}')].Name | [0]" --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_BUCKET}" ] && [ "${EXISTING_BUCKET}" != "None" ] && [ "${EXISTING_BUCKET}" != "null" ]; then
  UI_BUCKET="${EXISTING_BUCKET}"
  echo "   ✓ Using existing bucket: ${UI_BUCKET}"
else
  UI_BUCKET="${APP_NAME}-ui-${ACCOUNT_ID}-$(date +%s)"
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${UI_BUCKET}" --no-cli-pager >/dev/null
  else
    aws s3api create-bucket --bucket "${UI_BUCKET}" \
      --create-bucket-configuration LocationConstraint="${REGION}" --no-cli-pager >/dev/null
  fi
  echo "   ✓ Created bucket: ${UI_BUCKET}"
fi

# ============================================================
# 4. Create or find CloudFront Distribution
# ============================================================
echo ""
echo "4️⃣  Setting up CloudFront distribution..."
CF_DIST_ID=$(aws cloudfront list-distributions --no-cli-pager \
  --query "DistributionList.Items[?Comment=='${APP_NAME} UI'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "${CF_DIST_ID}" ] && [ "${CF_DIST_ID}" != "None" ] && [ "${CF_DIST_ID}" != "null" ]; then
  echo "   ✓ Distribution exists: ${CF_DIST_ID}"
  CF_DOMAIN=$(aws cloudfront get-distribution --id "${CF_DIST_ID}" --no-cli-pager \
    --query 'Distribution.DomainName' --output text)
else
  OAI_ID=$(aws cloudfront list-cloud-front-origin-access-identities --no-cli-pager \
    --query "CloudFrontOriginAccessIdentityList.Items[?Comment=='OAI for ${APP_NAME} UI'].Id | [0]" --output text 2>/dev/null || echo "")

  if [ -z "${OAI_ID}" ] || [ "${OAI_ID}" = "None" ] || [ "${OAI_ID}" = "null" ]; then
    OAI_RESPONSE=$(aws cloudfront create-cloud-front-origin-access-identity \
      --cloud-front-origin-access-identity-config "{\"CallerReference\":\"${APP_NAME}-$(date +%s)\",\"Comment\":\"OAI for ${APP_NAME} UI\"}" \
      --no-cli-pager)
    OAI_ID=$(echo "${OAI_RESPONSE}" | jq -r '.CloudFrontOriginAccessIdentity.Id')
    echo "   ✓ Created OAI: ${OAI_ID}"
  else
    echo "   ✓ OAI exists: ${OAI_ID}"
  fi

  OAI_CANONICAL=$(aws cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" --no-cli-pager \
    --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' --output text)

  aws s3api put-bucket-policy --bucket "${UI_BUCKET}" --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"CanonicalUser\": \"${OAI_CANONICAL}\"},
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${UI_BUCKET}/*\"
    }]
  }" --no-cli-pager
  echo "   ✓ Bucket policy updated"

  CF_RESPONSE=$(aws cloudfront create-distribution \
    --distribution-config "{
      \"CallerReference\": \"${APP_NAME}-$(date +%s)\",
      \"Comment\": \"${APP_NAME} UI\",
      \"Enabled\": true,
      \"DefaultRootObject\": \"index.html\",
      \"Origins\": {
        \"Quantity\": 1,
        \"Items\": [{
          \"Id\": \"S3-${UI_BUCKET}\",
          \"DomainName\": \"${UI_BUCKET}.s3.${REGION}.amazonaws.com\",
          \"S3OriginConfig\": {\"OriginAccessIdentity\": \"origin-access-identity/cloudfront/${OAI_ID}\"}
        }]
      },
      \"DefaultCacheBehavior\": {
        \"TargetOriginId\": \"S3-${UI_BUCKET}\",
        \"ViewerProtocolPolicy\": \"redirect-to-https\",
        \"AllowedMethods\": {
          \"Quantity\": 2,
          \"Items\": [\"GET\", \"HEAD\"],
          \"CachedMethods\": {\"Quantity\": 2, \"Items\": [\"GET\", \"HEAD\"]}
        },
        \"ForwardedValues\": {\"QueryString\": false, \"Cookies\": {\"Forward\": \"none\"}},
        \"MinTTL\": 0,
        \"DefaultTTL\": 86400,
        \"MaxTTL\": 31536000,
        \"Compress\": true
      },
      \"CustomErrorResponses\": {
        \"Quantity\": 1,
        \"Items\": [{
          \"ErrorCode\": 403,
          \"ResponsePagePath\": \"/index.html\",
          \"ResponseCode\": \"200\",
          \"ErrorCachingMinTTL\": 300
        }]
      },
      \"PriceClass\": \"PriceClass_100\"
    }" \
    --no-cli-pager)

  CF_DIST_ID=$(echo "${CF_RESPONSE}" | jq -r '.Distribution.Id')
  CF_DOMAIN=$(echo "${CF_RESPONSE}" | jq -r '.Distribution.DomainName')
  echo "   ✓ Created distribution: ${CF_DIST_ID}"
fi

echo "   ✓ Domain: ${CF_DOMAIN}"

# ============================================================
# 5. Update config.json
# ============================================================
echo ""
echo "5️⃣  Updating config.json..."

CONFIG_FILE="${UI_DIR}/config.json"
if [ -f "${CONFIG_FILE}" ]; then
  jq --arg userPoolId "${USER_POOL_ID}" \
     --arg clientId "${CLIENT_ID}" \
     --arg apiEndpoint "${API_ENDPOINT}" \
     '. + {userPoolId: $userPoolId, clientId: $clientId, apiEndpoint: $apiEndpoint}' \
     "${CONFIG_FILE}" > /tmp/config.json && mv /tmp/config.json "${CONFIG_FILE}"
  echo "   ✓ Updated config.json"
else
  echo "   ⚠️  config.json not found"
fi

# ============================================================
# 6. Upload UI files
# ============================================================
echo ""
echo "6️⃣  Uploading UI files to S3..."

if [ ! -d "${UI_DIR}" ]; then
  echo "   ❌ UI directory not found: ${UI_DIR}"
  exit 1
fi

shopt -s nullglob
for file in "${UI_DIR}"/*.html "${UI_DIR}"/*.js "${UI_DIR}"/*.css "${UI_DIR}"/*.json "${UI_DIR}"/*.svg; do
  if [ -f "${file}" ]; then
    filename=$(basename "${file}")
    if [ "${filename}" = "config-local.json" ]; then
      continue
    fi

    case "${filename}" in
      *.html) CONTENT_TYPE="text/html" ;;
      *.js) CONTENT_TYPE="application/javascript" ;;
      *.css) CONTENT_TYPE="text/css" ;;
      *.json) CONTENT_TYPE="application/json" ;;
      *.svg) CONTENT_TYPE="image/svg+xml" ;;
      *) CONTENT_TYPE="application/octet-stream" ;;
    esac

    aws s3 cp "${file}" "s3://${UI_BUCKET}/${filename}" \
      --content-type "${CONTENT_TYPE}" \
      --no-cli-pager >/dev/null
    echo "   ✓ Uploaded: ${filename}"
  fi
done
shopt -u nullglob

# ============================================================
# 7. Invalidate CloudFront cache
# ============================================================
echo ""
echo "7️⃣  Invalidating CloudFront cache..."
INVALIDATION=$(aws cloudfront create-invalidation \
  --distribution-id "${CF_DIST_ID}" \
  --paths "/*" \
  --no-cli-pager)

INVALIDATION_ID=$(echo "${INVALIDATION}" | jq -r '.Invalidation.Id')
echo "   ✓ Invalidation started: ${INVALIDATION_ID}"

# ============================================================
# 8. Wait for CloudFront
# ============================================================
echo ""
echo "8️⃣  Waiting for CloudFront to be reachable..."
UI_URL="https://${CF_DOMAIN}"

for i in {1..20}; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${UI_URL}" 2>/dev/null || echo "000")
  if [ "${HTTP_STATUS}" = "200" ]; then
    echo "   ✓ UI is reachable"
    break
  fi
  echo "   ⏳ HTTP status: ${HTTP_STATUS}"
  sleep 15
done

echo ""
echo "✅ UI Deployed Successfully"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 URL: ${UI_URL}"
echo "👤 Test users: admin, alice, bob"
echo "🔑 Password: Workshop123!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
