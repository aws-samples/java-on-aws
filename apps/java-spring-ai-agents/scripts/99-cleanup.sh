#!/bin/bash
set -e

echo "=============================================="
echo "99-cleanup.sh - Resource Cleanup"
echo "=============================================="
echo ""
echo "This script will delete all resources created by scripts 02-12."
echo "Press Ctrl+C within 10 seconds to cancel..."
sleep 10

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region --no-cli-pager)

echo ""
echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

# Helper function for safe deletion
delete_resource() {
    local name="$1"
    local check_cmd="$2"
    local delete_cmd="$3"

    echo -n "  ${name}... "
    if eval "${check_cmd}" >/dev/null 2>&1; then
        if eval "${delete_cmd}" >/dev/null 2>&1; then
            echo "deleted"
        else
            echo "failed (may require manual cleanup)"
        fi
    else
        echo "not found"
    fi
}

## 1. Delete AI Agent Runtime (08-aiagent-runtime.sh)

echo ""
echo "## Deleting AI Agent Runtime"

if [ -n "${AIAGENT_RUNTIME_ID}" ]; then
    echo -n "  aiagent runtime... "
    if aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${AIAGENT_RUNTIME_ID}" \
        --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; then
        aws bedrock-agentcore-control delete-agent-runtime \
            --agent-runtime-id "${AIAGENT_RUNTIME_ID}" \
            --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1 || true
        echo "deleting"
        echo -n "  waiting"
        while aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${AIAGENT_RUNTIME_ID}" \
            --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; do
            echo -n "."; sleep 5
        done && echo " done"
    else
        echo "not found"
    fi
fi

delete_resource "aiagent-runtime-role policy" \
    "aws iam get-role-policy --role-name aiagent-runtime-role --policy-name AgentCoreExecutionPolicy --no-cli-pager" \
    "aws iam delete-role-policy --role-name aiagent-runtime-role --policy-name AgentCoreExecutionPolicy --no-cli-pager"

delete_resource "aiagent-runtime-role" \
    "aws iam get-role --role-name aiagent-runtime-role --no-cli-pager" \
    "aws iam delete-role --role-name aiagent-runtime-role --no-cli-pager"

delete_resource "aiagent ECR repository" \
    "aws ecr describe-repositories --repository-names aiagent --region ${AWS_REGION} --no-cli-pager" \
    "aws ecr delete-repository --repository-name aiagent --region ${AWS_REGION} --force --no-cli-pager"

## 2. Delete AI Agent UI (09-aiagent-ui.sh)

echo ""
echo "## Deleting AI Agent UI"

if [ -n "${UI_DOMAIN}" ]; then
    DIST_ID=$(aws cloudfront list-distributions --no-cli-pager \
        --query "DistributionList.Items[?DomainName=='${UI_DOMAIN}'].Id | [0]" --output text 2>/dev/null || echo "None")

    if [ "${DIST_ID}" != "None" ] && [ -n "${DIST_ID}" ]; then
        echo -n "  CloudFront distribution... "

        # Get OAI ID before disabling
        OAI_ID=$(aws cloudfront get-distribution --id "${DIST_ID}" --no-cli-pager \
            --query "Distribution.DistributionConfig.Origins.Items[0].S3OriginConfig.OriginAccessIdentity" --output text 2>/dev/null | sed 's|origin-access-identity/cloudfront/||')

        # Disable distribution first
        ETAG=$(aws cloudfront get-distribution-config --id "${DIST_ID}" --no-cli-pager \
            --query 'ETag' --output text)
        aws cloudfront get-distribution-config --id "${DIST_ID}" --no-cli-pager \
            --query 'DistributionConfig' | jq '.Enabled = false' > /tmp/cf-disable.json
        aws cloudfront update-distribution --id "${DIST_ID}" --if-match "${ETAG}" \
            --distribution-config file:///tmp/cf-disable.json --no-cli-pager >/dev/null 2>&1 || true
        rm -f /tmp/cf-disable.json
        echo "disabled"

        echo -n "  waiting for distribution to deploy"
        while [ "$(aws cloudfront get-distribution --id "${DIST_ID}" --no-cli-pager \
            --query 'Distribution.Status' --output text 2>/dev/null)" != "Deployed" ]; do
            echo -n "."; sleep 10
        done && echo " done"

        echo -n "  deleting distribution... "
        ETAG=$(aws cloudfront get-distribution-config --id "${DIST_ID}" --no-cli-pager \
            --query 'ETag' --output text)
        aws cloudfront delete-distribution --id "${DIST_ID}" --if-match "${ETAG}" --no-cli-pager >/dev/null 2>&1 && echo "deleted" || echo "failed"

        # Delete OAI
        if [ -n "${OAI_ID}" ] && [ "${OAI_ID}" != "None" ]; then
            echo -n "  CloudFront OAI... "
            OAI_ETAG=$(aws cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" --no-cli-pager \
                --query 'ETag' --output text 2>/dev/null || echo "")
            if [ -n "${OAI_ETAG}" ]; then
                aws cloudfront delete-cloud-front-origin-access-identity --id "${OAI_ID}" --if-match "${OAI_ETAG}" \
                    --no-cli-pager >/dev/null 2>&1 && echo "deleted" || echo "failed"
            else
                echo "not found"
            fi
        fi
    else
        echo "  CloudFront distribution... not found"
    fi
fi

if [ -n "${UI_BUCKET}" ]; then
    echo -n "  UI S3 bucket... "
    if aws s3api head-bucket --bucket "${UI_BUCKET}" --no-cli-pager 2>/dev/null; then
        aws s3 rm "s3://${UI_BUCKET}" --recursive --no-cli-pager >/dev/null 2>&1 || true
        aws s3api delete-bucket --bucket "${UI_BUCKET}" --no-cli-pager >/dev/null 2>&1 && echo "deleted" || echo "failed"
    else
        echo "not found"
    fi
fi

## 3. Delete AI Agent Cognito (07-aiagent-cognito.sh)

echo ""
echo "## Deleting AI Agent Cognito"

if [ -n "${AIAGENT_USER_POOL_ID}" ]; then
    delete_resource "aiagent-user-pool" \
        "aws cognito-idp describe-user-pool --user-pool-id ${AIAGENT_USER_POOL_ID} --region ${AWS_REGION} --no-cli-pager" \
        "aws cognito-idp delete-user-pool --user-pool-id ${AIAGENT_USER_POOL_ID} --region ${AWS_REGION} --no-cli-pager"
fi

## 4. Delete Currency Lambda (11-mcp-currency.sh)

echo ""
echo "## Deleting Currency Lambda"

# Delete gateway target first
if [ -n "${GATEWAY_ID}" ]; then
    CURRENCY_TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
        --query "items[?name=='currency'].targetId | [0]" --output text 2>/dev/null || echo "None")

    if [ "${CURRENCY_TARGET_ID}" != "None" ] && [ -n "${CURRENCY_TARGET_ID}" ]; then
        delete_resource "currency gateway target" \
            "aws bedrock-agentcore-control get-gateway-target --gateway-identifier ${GATEWAY_ID} --target-id ${CURRENCY_TARGET_ID} --region ${AWS_REGION} --no-cli-pager" \
            "aws bedrock-agentcore-control delete-gateway-target --gateway-identifier ${GATEWAY_ID} --target-id ${CURRENCY_TARGET_ID} --region ${AWS_REGION} --no-cli-pager"
    fi
fi

delete_resource "mcp-currency Lambda" \
    "aws lambda get-function --function-name mcp-currency --region ${AWS_REGION} --no-cli-pager" \
    "aws lambda delete-function --function-name mcp-currency --region ${AWS_REGION} --no-cli-pager"

delete_resource "mcp-gateway-role CurrencyLambdaInvoke policy" \
    "aws iam get-role-policy --role-name mcp-gateway-role --policy-name CurrencyLambdaInvoke --no-cli-pager" \
    "aws iam delete-role-policy --role-name mcp-gateway-role --policy-name CurrencyLambdaInvoke --no-cli-pager"

delete_resource "mcp-currency-role policy" \
    "aws iam list-attached-role-policies --role-name mcp-currency-role --no-cli-pager" \
    "aws iam detach-role-policy --role-name mcp-currency-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole --no-cli-pager"

delete_resource "mcp-currency-role" \
    "aws iam get-role --role-name mcp-currency-role --no-cli-pager" \
    "aws iam delete-role --role-name mcp-currency-role --no-cli-pager"

## 5. Delete Gateway (06-mcp-gateway.sh)

echo ""
echo "## Deleting Gateway"

if [ -n "${GATEWAY_ID}" ]; then
    # Delete remaining targets and wait for each
    for TARGET_NAME in backoffice holidays; do
        TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
            --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
            --query "items[?name=='${TARGET_NAME}'].targetId | [0]" --output text 2>/dev/null || echo "None")

        if [ "${TARGET_ID}" != "None" ] && [ -n "${TARGET_ID}" ]; then
            echo -n "  ${TARGET_NAME} gateway target... "
            aws bedrock-agentcore-control delete-gateway-target \
                --gateway-identifier "${GATEWAY_ID}" --target-id "${TARGET_ID}" \
                --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1 || true
            echo "deleting"
            echo -n "    waiting"
            while aws bedrock-agentcore-control get-gateway-target \
                --gateway-identifier "${GATEWAY_ID}" --target-id "${TARGET_ID}" \
                --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; do
                echo -n "."; sleep 5
            done && echo " done"
        fi
    done

    echo -n "  mcp-gateway... "
    if aws bedrock-agentcore-control get-gateway --gateway-identifier "${GATEWAY_ID}" \
        --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; then
        aws bedrock-agentcore-control delete-gateway \
            --gateway-identifier "${GATEWAY_ID}" \
            --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1 || true
        echo "deleting"
        echo -n "  waiting"
        while aws bedrock-agentcore-control get-gateway --gateway-identifier "${GATEWAY_ID}" \
            --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; do
            echo -n "."; sleep 5
        done && echo " done"
    else
        echo "not found"
    fi
fi

# Delete credential providers
OAUTH_PROVIDER_ARN=$(aws bedrock-agentcore-control list-oauth2-credential-providers \
    --region ${AWS_REGION} --no-cli-pager \
    --query "credentialProviders[?name=='mcp-backoffice-oauth'].credentialProviderArn | [0]" --output text 2>/dev/null || echo "None")

if [ "${OAUTH_PROVIDER_ARN}" != "None" ] && [ -n "${OAUTH_PROVIDER_ARN}" ]; then
    delete_resource "mcp-backoffice-oauth provider" \
        "true" \
        "aws bedrock-agentcore-control delete-oauth2-credential-provider --credential-provider-arn ${OAUTH_PROVIDER_ARN} --region ${AWS_REGION} --no-cli-pager"
fi

APIKEY_PROVIDER_ARN=$(aws bedrock-agentcore-control list-api-key-credential-providers \
    --region ${AWS_REGION} --no-cli-pager \
    --query "credentialProviders[?name=='mcp-holidays-apikey-provider'].credentialProviderArn | [0]" --output text 2>/dev/null || echo "None")

if [ "${APIKEY_PROVIDER_ARN}" != "None" ] && [ -n "${APIKEY_PROVIDER_ARN}" ]; then
    delete_resource "mcp-holidays-apikey-provider" \
        "true" \
        "aws bedrock-agentcore-control delete-api-key-credential-provider --credential-provider-arn ${APIKEY_PROVIDER_ARN} --region ${AWS_REGION} --no-cli-pager"
fi

delete_resource "mcp-gateway-role policy" \
    "aws iam get-role-policy --role-name mcp-gateway-role --policy-name GatewayPolicy --no-cli-pager" \
    "aws iam delete-role-policy --role-name mcp-gateway-role --policy-name GatewayPolicy --no-cli-pager"

delete_resource "mcp-gateway-role" \
    "aws iam get-role --role-name mcp-gateway-role --no-cli-pager" \
    "aws iam delete-role --role-name mcp-gateway-role --no-cli-pager"

## 6. Delete MCP Runtime (05-mcp-runtime.sh)

echo ""
echo "## Deleting MCP Runtime"

if [ -n "${MCP_RUNTIME_ID}" ]; then
    echo -n "  backoffice runtime... "
    if aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${MCP_RUNTIME_ID}" \
        --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; then
        aws bedrock-agentcore-control delete-agent-runtime \
            --agent-runtime-id "${MCP_RUNTIME_ID}" \
            --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1 || true
        echo "deleting"
        echo -n "  waiting"
        while aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${MCP_RUNTIME_ID}" \
            --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; do
            echo -n "."; sleep 5
        done && echo " done"
    else
        echo "not found"
    fi
fi

delete_resource "backoffice-role policy" \
    "aws iam get-role-policy --role-name backoffice-role --policy-name AgentCorePolicy --no-cli-pager" \
    "aws iam delete-role-policy --role-name backoffice-role --policy-name AgentCorePolicy --no-cli-pager"

delete_resource "backoffice-role" \
    "aws iam get-role --role-name backoffice-role --no-cli-pager" \
    "aws iam delete-role --role-name backoffice-role --no-cli-pager"

delete_resource "backoffice ECR repository" \
    "aws ecr describe-repositories --repository-names backoffice --region ${AWS_REGION} --no-cli-pager" \
    "aws ecr delete-repository --repository-name backoffice --region ${AWS_REGION} --force --no-cli-pager"

## 7. Delete MCP Cognito (04-mcp-cognito.sh)

echo ""
echo "## Deleting MCP Cognito"

if [ -n "${GATEWAY_POOL_ID}" ]; then
    # Delete domain first
    COGNITO_DOMAIN=$(aws cognito-idp describe-user-pool \
        --user-pool-id "${GATEWAY_POOL_ID}" --region ${AWS_REGION} \
        --no-cli-pager --query 'UserPool.Domain' --output text 2>/dev/null || echo "None")

    if [ "${COGNITO_DOMAIN}" != "None" ] && [ -n "${COGNITO_DOMAIN}" ]; then
        delete_resource "mcp-gateway Cognito domain" \
            "true" \
            "aws cognito-idp delete-user-pool-domain --domain ${COGNITO_DOMAIN} --user-pool-id ${GATEWAY_POOL_ID} --region ${AWS_REGION} --no-cli-pager"
    fi

    delete_resource "mcp-gateway-pool" \
        "aws cognito-idp describe-user-pool --user-pool-id ${GATEWAY_POOL_ID} --region ${AWS_REGION} --no-cli-pager" \
        "aws cognito-idp delete-user-pool --user-pool-id ${GATEWAY_POOL_ID} --region ${AWS_REGION} --no-cli-pager"
fi

## 8. Delete Knowledge Base (03-knowledgebase.sh)

echo ""
echo "## Deleting Knowledge Base"

KB_ID="${SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID}"
if [ -n "${KB_ID}" ]; then
    # Delete data sources first
    DS_IDS=$(aws bedrock-agent list-data-sources --knowledge-base-id "${KB_ID}" --no-cli-pager \
        --query 'dataSourceSummaries[].dataSourceId' --output text 2>/dev/null || echo "")

    for DS_ID in ${DS_IDS}; do
        delete_resource "data source ${DS_ID}" \
            "aws bedrock-agent get-data-source --knowledge-base-id ${KB_ID} --data-source-id ${DS_ID} --no-cli-pager" \
            "aws bedrock-agent delete-data-source --knowledge-base-id ${KB_ID} --data-source-id ${DS_ID} --no-cli-pager"
    done

    delete_resource "aiagent-kb" \
        "aws bedrock-agent get-knowledge-base --knowledge-base-id ${KB_ID} --no-cli-pager" \
        "aws bedrock-agent delete-knowledge-base --knowledge-base-id ${KB_ID} --no-cli-pager"
fi

delete_resource "aiagent-kb-role policy" \
    "aws iam get-role-policy --role-name aiagent-kb-role --policy-name aiagent-kb-policy --no-cli-pager" \
    "aws iam delete-role-policy --role-name aiagent-kb-role --policy-name aiagent-kb-policy --no-cli-pager"

delete_resource "aiagent-kb-role" \
    "aws iam get-role --role-name aiagent-kb-role --no-cli-pager" \
    "aws iam delete-role --role-name aiagent-kb-role --no-cli-pager"

# Delete S3 buckets
DATA_BUCKET="aiagent-kb-data-${ACCOUNT_ID}"
VECTOR_BUCKET="aiagent-kb-vectors-${ACCOUNT_ID}"

echo -n "  KB data bucket... "
if aws s3api head-bucket --bucket "${DATA_BUCKET}" --no-cli-pager 2>/dev/null; then
    aws s3 rm "s3://${DATA_BUCKET}" --recursive --no-cli-pager >/dev/null 2>&1 || true
    aws s3api delete-bucket --bucket "${DATA_BUCKET}" --no-cli-pager >/dev/null 2>&1 && echo "deleted" || echo "failed"
else
    echo "not found"
fi

# Delete vector index first, then vector bucket
INDEX_EXISTS=$(aws s3vectors list-indexes --vector-bucket-name "${VECTOR_BUCKET}" --no-cli-pager \
    --query "indexes[?indexName=='aiagent-index'].indexName" --output text 2>/dev/null || echo "")

if [ -n "${INDEX_EXISTS}" ]; then
    delete_resource "aiagent-index" \
        "true" \
        "aws s3vectors delete-index --vector-bucket-name ${VECTOR_BUCKET} --index-name aiagent-index --no-cli-pager"
fi

VECTOR_BUCKET_EXISTS=$(aws s3vectors list-vector-buckets --no-cli-pager \
    --query "vectorBuckets[?name=='${VECTOR_BUCKET}'].name" --output text 2>/dev/null || echo "")

if [ -n "${VECTOR_BUCKET_EXISTS}" ]; then
    delete_resource "KB vector bucket" \
        "true" \
        "aws s3vectors delete-vector-bucket --vector-bucket-name ${VECTOR_BUCKET} --no-cli-pager"
fi

## 9. Delete Memory (02-memory.sh)

echo ""
echo "## Deleting Memory"

if [ -n "${AGENTCORE_MEMORY_MEMORY_ID}" ]; then
    echo -n "  aiagent_memory... "
    if aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
        --no-cli-pager >/dev/null 2>&1; then
        aws bedrock-agentcore-control delete-memory \
            --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
            --no-cli-pager >/dev/null 2>&1 || true
        echo "deleting"
        echo -n "  waiting"
        while aws bedrock-agentcore-control get-memory --memory-id "${AGENTCORE_MEMORY_MEMORY_ID}" \
            --no-cli-pager >/dev/null 2>&1; do
            echo -n "."; sleep 5
        done && echo " done"
    else
        echo "not found"
    fi
fi

## 10. Delete DynamoDB tables (created by backoffice app)

echo ""
echo "## Deleting DynamoDB tables"

for TABLE in backoffice-trips backoffice-expenses; do
    delete_resource "${TABLE}" \
        "aws dynamodb describe-table --table-name ${TABLE} --region ${AWS_REGION} --no-cli-pager" \
        "aws dynamodb delete-table --table-name ${TABLE} --region ${AWS_REGION} --no-cli-pager"
done

## 11. Clean up environment file

echo ""
echo "## Cleaning up environment file"

if [ -f ~/environment/.envrc ]; then
    echo "Removing resource IDs from ~/environment/.envrc"

    # Keep only basic variables
    grep -E "^export (AWS_REGION|ACCOUNT_ID|IDE_PASSWORD)=" ~/environment/.envrc > /tmp/envrc-clean.tmp 2>/dev/null || true
    mv /tmp/envrc-clean.tmp ~/environment/.envrc 2>/dev/null || touch ~/environment/.envrc

    echo "Environment file cleaned"
fi

echo ""
echo "=============================================="
echo "Cleanup complete!"
echo "=============================================="
echo ""
echo "Note: Some resources may take additional time to fully delete."
echo "If you encounter issues, wait a few minutes and run this script again."
