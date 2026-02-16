#!/bin/bash
set -e

echo "=============================================="
echo "09-aiagent-ui.sh - AI Agent UI Deployment"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${AIAGENT_USER_POOL_ID}" ] || [ -z "${AIAGENT_CLIENT_ID}" ] || [ -z "${AIAGENT_ENDPOINT}" ]; then
    echo "Error: Missing required variables. Run 07-aiagent-cognito.sh and 08-aiagent-runtime.sh first."
    exit 1
fi

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Creating the S3 bucket

echo ""
echo "## Deploying the UI"
echo "1. Create the S3 bucket"

# Check if bucket already exists in environment
if [ -n "${UI_BUCKET}" ]; then
    BUCKET_EXISTS=$(aws s3api head-bucket --bucket "${UI_BUCKET}" 2>/dev/null && echo "yes" || echo "no")
    if [ "${BUCKET_EXISTS}" = "yes" ]; then
        echo "S3 bucket already exists: ${UI_BUCKET}"
    else
        unset UI_BUCKET
    fi
fi

if [ -z "${UI_BUCKET}" ]; then
    UI_BUCKET="aiagent-ui-${ACCOUNT_ID}-$(date +%s)"
    echo "Creating S3 bucket: ${UI_BUCKET}"

    if [ "${AWS_REGION}" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "${UI_BUCKET}" --no-cli-pager
    else
        aws s3api create-bucket --bucket "${UI_BUCKET}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}" --no-cli-pager
    fi

    # Save to environment
    sed -i.bak '/UI_BUCKET=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export UI_BUCKET=${UI_BUCKET}" >> ~/environment/.envrc
fi

## Creating the CloudFront distribution

echo ""
echo "2. Create the CloudFront distribution"

# Check if distribution already exists
if [ -n "${UI_DOMAIN}" ]; then
    echo "CloudFront distribution already configured: ${UI_DOMAIN}"
else
    echo "Creating CloudFront OAI and distribution..."

    OAI_ID=$(aws cloudfront create-cloud-front-origin-access-identity \
        --cloud-front-origin-access-identity-config \
        "{\"CallerReference\":\"aiagent-$(date +%s)\",\"Comment\":\"OAI for aiagent UI\"}" \
        --no-cli-pager --query 'CloudFrontOriginAccessIdentity.Id' --output text)

    OAI_CANONICAL=$(aws cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" \
        --no-cli-pager --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' --output text)

    cat > /tmp/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"CanonicalUser": "${OAI_CANONICAL}"},
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${UI_BUCKET}/*"
  }]
}
EOF

    aws s3api put-bucket-policy --bucket "${UI_BUCKET}" \
        --policy file:///tmp/bucket-policy.json --no-cli-pager

    cat > /tmp/cf-distribution.json << EOF
{
  "CallerReference": "aiagent-$(date +%s)",
  "Comment": "aiagent UI",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3-${UI_BUCKET}",
      "DomainName": "${UI_BUCKET}.s3.${AWS_REGION}.amazonaws.com",
      "S3OriginConfig": {
        "OriginAccessIdentity": "origin-access-identity/cloudfront/${OAI_ID}"
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-${UI_BUCKET}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
    },
    "ForwardedValues": {"QueryString": false, "Cookies": {"Forward": "none"}},
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000,
    "Compress": true
  },
  "CustomErrorResponses": {
    "Quantity": 1,
    "Items": [{
      "ErrorCode": 403,
      "ResponsePagePath": "/index.html",
      "ResponseCode": "200",
      "ErrorCachingMinTTL": 300
    }]
  },
  "PriceClass": "PriceClass_100"
}
EOF

    UI_DOMAIN=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/cf-distribution.json \
        --no-cli-pager --query 'Distribution.DomainName' --output text)

    rm -f /tmp/bucket-policy.json /tmp/cf-distribution.json

    # Save to environment
    sed -i.bak '/UI_DOMAIN=/d' ~/environment/.envrc 2>/dev/null || true
    echo "export UI_DOMAIN=${UI_DOMAIN}" >> ~/environment/.envrc
fi

## Uploading the files

echo ""
echo "3. Generate config and upload files"

# Generate config.json
UI_DIR="${SCRIPT_DIR}/../aiagent/src/main/resources/static"

cat > "${UI_DIR}/config.json" << EOF
{
  "userPoolId": "${AIAGENT_USER_POOL_ID}",
  "clientId": "${AIAGENT_CLIENT_ID}",
  "apiEndpoint": "${AIAGENT_ENDPOINT}",
  "enableAttachments": true
}
EOF

echo "Uploading static files..."
for file in ${UI_DIR}/*.html ${UI_DIR}/*.js ${UI_DIR}/*.css ${UI_DIR}/*.json ${UI_DIR}/*.svg; do
    if [ -f "${file}" ]; then
        filename=$(basename "${file}")
        case "${filename}" in
            *.html) CONTENT_TYPE="text/html" ;;
            *.js) CONTENT_TYPE="application/javascript" ;;
            *.css) CONTENT_TYPE="text/css" ;;
            *.json) CONTENT_TYPE="application/json" ;;
            *.svg) CONTENT_TYPE="image/svg+xml" ;;
        esac
        aws s3 cp "${file}" "s3://${UI_BUCKET}/${filename}" \
            --content-type "${CONTENT_TYPE}" --no-cli-pager
    fi
done

## Waiting for CloudFront

echo ""
echo "4. Wait for CloudFront to become available"

echo -n "Waiting for CloudFront"
RETRY_COUNT=0
MAX_RETRIES=40
while [ "$(curl -s -o /dev/null -w "%{http_code}" "https://${UI_DOMAIN}" 2>/dev/null)" != "200" ]; do
    echo -n "."
    sleep 15
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ]; then
        echo " timeout (CloudFront may still be propagating)"
        break
    fi
done
if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
    echo " READY"
fi

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "UI deployment complete!"
echo "=============================================="
echo ""
echo "Environment variables saved to ~/environment/.envrc:"
echo "  UI_BUCKET=${UI_BUCKET}"
echo "  UI_DOMAIN=${UI_DOMAIN}"
echo ""
echo "UI URL: https://${UI_DOMAIN}"
echo ""
echo "Test users: admin, alice, bob (password: \${IDE_PASSWORD})"
