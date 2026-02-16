#!/bin/bash
set -e

echo "=============================================="
echo "03-knowledgebase.sh - Bedrock Knowledge Base Setup"
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

DATA_BUCKET="aiagent-kb-data-${ACCOUNT_ID}"
VECTOR_BUCKET="aiagent-kb-vectors-${ACCOUNT_ID}"
KB_ROLE="aiagent-kb-role"

## Creating S3 buckets and vector index

echo ""
echo "## Creating S3 buckets and vector index"
echo "1. Create S3 buckets and vector index"

# Check if data bucket exists
if aws s3api head-bucket --bucket "${DATA_BUCKET}" 2>/dev/null; then
    echo "Data bucket already exists: ${DATA_BUCKET}"
else
    echo "Creating data bucket: ${DATA_BUCKET}"
    aws s3api create-bucket --bucket "${DATA_BUCKET}" --no-cli-pager
fi

# Check if vector bucket exists
VECTOR_BUCKET_EXISTS=$(aws s3vectors list-vector-buckets --no-cli-pager \
    --query "vectorBuckets[?name=='${VECTOR_BUCKET}'].name" --output text 2>/dev/null || echo "")

if [ -n "${VECTOR_BUCKET_EXISTS}" ]; then
    echo "Vector bucket already exists: ${VECTOR_BUCKET}"
else
    echo "Creating vector bucket: ${VECTOR_BUCKET}"
    aws s3vectors create-vector-bucket --vector-bucket-name "${VECTOR_BUCKET}" --no-cli-pager
fi

# Check if index exists
INDEX_EXISTS=$(aws s3vectors list-indexes --vector-bucket-name "${VECTOR_BUCKET}" --no-cli-pager \
    --query "indexes[?indexName=='aiagent-index'].indexName" --output text 2>/dev/null || echo "")

if [ -n "${INDEX_EXISTS}" ]; then
    echo "Vector index already exists: aiagent-index"
else
    echo "Creating vector index: aiagent-index"
    aws s3vectors create-index --vector-bucket-name "${VECTOR_BUCKET}" \
        --index-name "aiagent-index" --data-type "float32" \
        --dimension 1024 --distance-metric "cosine" --no-cli-pager
fi

## Creating IAM role

echo ""
echo "2. Create IAM role for the Knowledge Base"

# Check if role exists
if aws iam get-role --role-name "${KB_ROLE}" --no-cli-pager >/dev/null 2>&1; then
    echo "IAM role already exists: ${KB_ROLE}"
else
    echo "Creating IAM role: ${KB_ROLE}"
    aws iam create-role --role-name "${KB_ROLE}" \
        --permissions-boundary "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "bedrock.amazonaws.com"},
                "Action": "sts:AssumeRole",
                "Condition": {
                    "StringEquals": {"aws:SourceAccount": "'${ACCOUNT_ID}'"},
                    "ArnLike": {"aws:SourceArn": "arn:aws:bedrock:'${AWS_REGION}':'${ACCOUNT_ID}':knowledge-base/*"}
                }
            }]
        }' --no-cli-pager

    aws iam put-role-policy --role-name "${KB_ROLE}" --policy-name "aiagent-kb-policy" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {"Effect": "Allow", "Action": ["s3:GetObject", "s3:ListBucket"],
                 "Resource": ["arn:aws:s3:::'${DATA_BUCKET}'", "arn:aws:s3:::'${DATA_BUCKET}'/*"]},
                {"Effect": "Allow", "Action": ["bedrock:InvokeModel"],
                 "Resource": ["arn:aws:bedrock:'${AWS_REGION}'::foundation-model/amazon.titan-embed-text-v2:0"]},
                {"Effect": "Allow", "Action": ["s3vectors:*"],
                 "Resource": ["arn:aws:s3vectors:'${AWS_REGION}':'${ACCOUNT_ID}':bucket/'${VECTOR_BUCKET}'",
                              "arn:aws:s3vectors:'${AWS_REGION}':'${ACCOUNT_ID}':bucket/'${VECTOR_BUCKET}'/*"]}
            ]
        }' --no-cli-pager

    echo -n "Waiting for role propagation" && sleep 10 && echo " done"
fi

## Creating the Knowledge Base

echo ""
echo "3. Create the Knowledge Base"

# Check if KB already exists by name
EXISTING_KB_ID=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
    --query "knowledgeBaseSummaries[?name=='aiagent-kb'].knowledgeBaseId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_KB_ID}" != "None" ] && [ -n "${EXISTING_KB_ID}" ]; then
    echo "Knowledge Base already exists: ${EXISTING_KB_ID}"
    KB_ID="${EXISTING_KB_ID}"
else
    echo "Creating Knowledge Base: aiagent-kb"
    KB_ID=$(aws bedrock-agent create-knowledge-base --name "aiagent-kb" \
        --description "Knowledge base for AI agent policies" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${KB_ROLE}" \
        --knowledge-base-configuration '{
            "type": "VECTOR",
            "vectorKnowledgeBaseConfiguration": {
                "embeddingModelArn": "arn:aws:bedrock:'${AWS_REGION}'::foundation-model/amazon.titan-embed-text-v2:0"
            }
        }' \
        --storage-configuration '{
            "type": "S3_VECTORS",
            "s3VectorsConfiguration": {
                "vectorBucketArn": "arn:aws:s3vectors:'${AWS_REGION}':'${ACCOUNT_ID}':bucket/'${VECTOR_BUCKET}'",
                "indexName": "aiagent-index"
            }
        }' --no-cli-pager --query 'knowledgeBase.knowledgeBaseId' --output text)

    echo -n "Waiting for knowledge base"
    while [ "$(aws bedrock-agent get-knowledge-base --knowledge-base-id ${KB_ID} \
        --no-cli-pager --query 'knowledgeBase.status' --output text)" != "ACTIVE" ]; do
        echo -n "."; sleep 5
    done && echo " ACTIVE"
fi

# Save KB ID to environment
if ! grep -q "SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID=${KB_ID}" ~/environment/.envrc 2>/dev/null; then
    sed -i.bak '/SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID/d' ~/environment/.envrc 2>/dev/null || true
    echo "export SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID=${KB_ID}" >> ~/environment/.envrc
fi

## Creating data source and ingesting documents

echo ""
echo "4. Create data source, upload documents, and start ingestion"

# Check if data source exists
EXISTING_DS_ID=$(aws bedrock-agent list-data-sources --knowledge-base-id "${KB_ID}" --no-cli-pager \
    --query "dataSourceSummaries[?name=='aiagent-policies'].dataSourceId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_DS_ID}" != "None" ] && [ -n "${EXISTING_DS_ID}" ]; then
    echo "Data source already exists: ${EXISTING_DS_ID}"
    DS_ID="${EXISTING_DS_ID}"
else
    echo "Creating data source: aiagent-policies"
    DS_ID=$(aws bedrock-agent create-data-source \
        --knowledge-base-id "${KB_ID}" \
        --name "aiagent-policies" \
        --data-source-configuration '{
            "type": "S3",
            "s3Configuration": {
                "bucketArn": "arn:aws:s3:::'${DATA_BUCKET}'",
                "inclusionPrefixes": ["policies/"]
            }
        }' --no-cli-pager --query 'dataSource.dataSourceId' --output text)
fi

# Upload policy documents
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Uploading policy documents..."
aws s3 cp "${SCRIPT_DIR}/../aiagent/samples/policy-travel.md" \
    s3://${DATA_BUCKET}/policies/policy-travel.md --no-cli-pager
aws s3 cp "${SCRIPT_DIR}/../aiagent/samples/policy-expense.md" \
    s3://${DATA_BUCKET}/policies/policy-expense.md --no-cli-pager

# Start ingestion job
echo "Starting ingestion job..."
JOB_ID=$(aws bedrock-agent start-ingestion-job \
    --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" \
    --no-cli-pager --query 'ingestionJob.ingestionJobId' --output text)

echo -n "Waiting for ingestion"
while [ "$(aws bedrock-agent get-ingestion-job --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" --ingestion-job-id "${JOB_ID}" \
    --no-cli-pager --query 'ingestionJob.status' --output text)" = "IN_PROGRESS" ]; do
    echo -n "."; sleep 5
done && echo " COMPLETE"

# Clean up backup files
rm -f ~/environment/.envrc.bak

echo ""
echo "=============================================="
echo "Knowledge Base setup complete!"
echo "=============================================="
echo ""
echo "Environment variable saved to ~/environment/.envrc:"
echo "  SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID=${KB_ID}"
