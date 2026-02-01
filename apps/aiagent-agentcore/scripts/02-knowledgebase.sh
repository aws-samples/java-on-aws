#!/bin/bash
# ============================================================
# 02-knowledgebase.sh - Deploy Bedrock Knowledge Base
# ============================================================
# Creates KB with S3 Vectors storage and Nova embeddings
# Uploads policy documents and starts ingestion
# Idempotent - safe to run multiple times
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)

# Resource names
KB_NAME="${APP_NAME}-kb"
DATA_BUCKET="${APP_NAME}-kb-data-${ACCOUNT_ID}-$(date +%s)"
VECTOR_BUCKET="${APP_NAME}-kb-vectors-${ACCOUNT_ID}-$(date +%s)"
KB_ROLE="${APP_NAME}-kb-role"
DATA_SOURCE="${APP_NAME}-policies"
VECTOR_INDEX="${APP_NAME}-index"

# Embedding model
EMBEDDING_MODEL="arn:aws:bedrock:${REGION}::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLES_DIR="${SCRIPT_DIR}/../aiagent/samples"

echo "📚 Creating Bedrock Knowledge Base"
echo ""
echo "Region: ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo "KB Name: ${KB_NAME}"
echo ""

# ============================================================
# 1. Create S3 Data Bucket
# ============================================================
echo "1️⃣  Creating data bucket"

# Check for existing bucket with our prefix
EXISTING_DATA_BUCKET=$(aws s3api list-buckets --no-cli-pager \
  --query "Buckets[?starts_with(Name, '${APP_NAME}-kb-data-${ACCOUNT_ID}')].Name | [0]" --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_DATA_BUCKET}" ] && [ "${EXISTING_DATA_BUCKET}" != "None" ] && [ "${EXISTING_DATA_BUCKET}" != "null" ]; then
  DATA_BUCKET="${EXISTING_DATA_BUCKET}"
  echo "   ✓ Using existing bucket: ${DATA_BUCKET}"
else
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${DATA_BUCKET}" --no-cli-pager >/dev/null
  else
    aws s3api create-bucket --bucket "${DATA_BUCKET}" \
      --create-bucket-configuration LocationConstraint="${REGION}" --no-cli-pager >/dev/null
  fi
  echo "   ✓ Created bucket: ${DATA_BUCKET}"
fi

# ============================================================
# 2. Create S3 Vectors Bucket
# ============================================================
echo ""
echo "2️⃣  Creating S3 Vectors bucket"

# Check for existing vector bucket
EXISTING_VECTOR_BUCKET=$(aws s3vectors list-vector-buckets --no-cli-pager \
  --query "vectorBuckets[?starts_with(name, '${APP_NAME}-kb-vectors-${ACCOUNT_ID}')].name | [0]" --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_VECTOR_BUCKET}" ] && [ "${EXISTING_VECTOR_BUCKET}" != "None" ] && [ "${EXISTING_VECTOR_BUCKET}" != "null" ]; then
  VECTOR_BUCKET="${EXISTING_VECTOR_BUCKET}"
  echo "   ✓ Using existing vector bucket: ${VECTOR_BUCKET}"
else
  aws s3vectors create-vector-bucket --vector-bucket-name "${VECTOR_BUCKET}" --no-cli-pager >/dev/null
  echo "   ✓ Created vector bucket: ${VECTOR_BUCKET}"
fi

VECTOR_BUCKET_ARN="arn:aws:s3vectors:${REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}"

# ============================================================
# 3. Create Vector Index
# ============================================================
echo ""
echo "3️⃣  Creating vector index: ${VECTOR_INDEX}"
if aws s3vectors get-index --vector-bucket-name "${VECTOR_BUCKET}" --index-name "${VECTOR_INDEX}" --no-cli-pager 2>/dev/null; then
  echo "   ✓ Vector index already exists"
else
  # Nova 2 multimodal embeddings uses 3072 dimensions by default
  aws s3vectors create-index \
    --vector-bucket-name "${VECTOR_BUCKET}" \
    --index-name "${VECTOR_INDEX}" \
    --data-type "float32" \
    --dimension 3072 \
    --distance-metric "cosine" \
    --no-cli-pager >/dev/null
  echo "   ✓ Created vector index"
fi

# ============================================================
# 4. Create IAM Role
# ============================================================
echo ""
echo "4️⃣  Creating IAM role: ${KB_ROLE}"

# Check if workshop boundary exists
BOUNDARY_ARN=""
if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" --no-cli-pager >/dev/null 2>&1; then
  BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary"
fi

if aws iam get-role --role-name "${KB_ROLE}" --no-cli-pager 2>/dev/null; then
  echo "   ✓ Role already exists"
else
  aws iam create-role \
    --role-name "${KB_ROLE}" \
    ${BOUNDARY_ARN:+--permissions-boundary "${BOUNDARY_ARN}"} \
    --assume-role-policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Principal\": {\"Service\": \"bedrock.amazonaws.com\"},
        \"Action\": \"sts:AssumeRole\",
        \"Condition\": {
          \"StringEquals\": {\"aws:SourceAccount\": \"${ACCOUNT_ID}\"},
          \"ArnLike\": {\"aws:SourceArn\": \"arn:aws:bedrock:${REGION}:${ACCOUNT_ID}:knowledge-base/*\"}
        }
      }]
    }" \
    --no-cli-pager >/dev/null
  echo "   ✓ Created role"
fi

# Attach policies
echo "   Attaching policies..."
aws iam put-role-policy \
  --role-name "${KB_ROLE}" \
  --policy-name "${APP_NAME}-kb-s3-policy" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"s3:GetObject\", \"s3:PutObject\", \"s3:DeleteObject\", \"s3:ListBucket\"],
      \"Resource\": [\"arn:aws:s3:::${DATA_BUCKET}\", \"arn:aws:s3:::${DATA_BUCKET}/*\"]
    }]
  }" \
  --no-cli-pager

aws iam put-role-policy \
  --role-name "${KB_ROLE}" \
  --policy-name "${APP_NAME}-kb-bedrock-policy" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"bedrock:InvokeModel\"],
      \"Resource\": [\"${EMBEDDING_MODEL}\"]
    }]
  }" \
  --no-cli-pager

aws iam put-role-policy \
  --role-name "${KB_ROLE}" \
  --policy-name "${APP_NAME}-kb-s3vectors-policy" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [
        \"s3vectors:CreateIndex\", \"s3vectors:DeleteIndex\", \"s3vectors:GetIndex\",
        \"s3vectors:ListIndexes\", \"s3vectors:PutVectors\", \"s3vectors:GetVectors\",
        \"s3vectors:DeleteVectors\", \"s3vectors:QueryVectors\", \"s3vectors:ListVectors\"
      ],
      \"Resource\": [\"${VECTOR_BUCKET_ARN}\", \"${VECTOR_BUCKET_ARN}/*\"]
    }]
  }" \
  --no-cli-pager

echo "   ✓ Policies attached"
echo "   Waiting for role propagation..."
sleep 10

# ============================================================
# 5. Create Knowledge Base
# ============================================================
echo ""
echo "5️⃣  Creating Knowledge Base: ${KB_NAME}"
KB_ID=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
  --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" \
  --output text 2>/dev/null || echo "")

if [ -n "${KB_ID}" ] && [ "${KB_ID}" != "None" ] && [ "${KB_ID}" != "null" ]; then
  echo "   ✓ Knowledge Base already exists: ${KB_ID}"
else
  KB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${KB_ROLE}"

  KB_RESPONSE=$(aws bedrock-agent create-knowledge-base \
    --name "${KB_NAME}" \
    --description "Knowledge base for AI Agent policies" \
    --role-arn "${KB_ROLE_ARN}" \
    --knowledge-base-configuration "{
      \"type\": \"VECTOR\",
      \"vectorKnowledgeBaseConfiguration\": {
        \"embeddingModelArn\": \"${EMBEDDING_MODEL}\",
        \"supplementalDataStorageConfiguration\": {
          \"storageLocations\": [{
            \"type\": \"S3\",
            \"s3Location\": {\"uri\": \"s3://${DATA_BUCKET}/\"}
          }]
        }
      }
    }" \
    --storage-configuration "{
      \"type\": \"S3_VECTORS\",
      \"s3VectorsConfiguration\": {
        \"vectorBucketArn\": \"${VECTOR_BUCKET_ARN}\",
        \"indexName\": \"${VECTOR_INDEX}\"
      }
    }" \
    --no-cli-pager)

  KB_ID=$(echo "${KB_RESPONSE}" | jq -r '.knowledgeBase.knowledgeBaseId')
  echo "   ✓ Created Knowledge Base: ${KB_ID}"

  # Wait for KB to be active
  echo "   Waiting for KB to become ACTIVE..."
  for i in {1..30}; do
    STATUS=$(aws bedrock-agent get-knowledge-base --knowledge-base-id "${KB_ID}" \
      --query 'knowledgeBase.status' --output text --no-cli-pager 2>/dev/null || echo "UNKNOWN")

    if [ "${STATUS}" = "ACTIVE" ]; then
      echo "   ✓ Knowledge Base is ACTIVE"
      break
    elif [ "${STATUS}" = "FAILED" ]; then
      echo "   ❌ Knowledge Base creation FAILED"
      exit 1
    fi

    if [ $((i % 5)) -eq 0 ]; then
      echo "   ⏳ Status: ${STATUS}"
    fi
    sleep 5
  done
fi

# ============================================================
# 6. Create Data Source
# ============================================================
echo ""
echo "6️⃣  Creating Data Source: ${DATA_SOURCE}"
DS_ID=$(aws bedrock-agent list-data-sources \
  --knowledge-base-id "${KB_ID}" \
  --query "dataSourceSummaries[?name=='${DATA_SOURCE}'].dataSourceId | [0]" \
  --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "${DS_ID}" ] && [ "${DS_ID}" != "None" ] && [ "${DS_ID}" != "null" ]; then
  echo "   ✓ Data Source already exists: ${DS_ID}"
else
  DS_RESPONSE=$(aws bedrock-agent create-data-source \
    --knowledge-base-id "${KB_ID}" \
    --name "${DATA_SOURCE}" \
    --description "Policy documents" \
    --data-source-configuration "{
      \"type\": \"S3\",
      \"s3Configuration\": {
        \"bucketArn\": \"arn:aws:s3:::${DATA_BUCKET}\",
        \"inclusionPrefixes\": [\"policies/\"]
      }
    }" \
    --no-cli-pager)

  DS_ID=$(echo "${DS_RESPONSE}" | jq -r '.dataSource.dataSourceId')
  echo "   ✓ Created Data Source: ${DS_ID}"
fi

# ============================================================
# 7. Upload Documents
# ============================================================
echo ""
echo "7️⃣  Uploading policy documents..."
if [ ! -d "${SAMPLES_DIR}" ]; then
  echo "   ⚠️  Samples directory not found: ${SAMPLES_DIR}"
  echo "   Skipping document upload"
else
  FILE_COUNT=$(find "${SAMPLES_DIR}" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "   Found ${FILE_COUNT} documents"

  for file in "${SAMPLES_DIR}"/*.md; do
    if [ -f "${file}" ]; then
      filename=$(basename "${file}")
      aws s3 cp "${file}" "s3://${DATA_BUCKET}/policies/${filename}" --no-cli-pager >/dev/null
      echo "   ✓ Uploaded: ${filename}"
    fi
  done
fi

# ============================================================
# 8. Start Ingestion
# ============================================================
echo ""
echo "8️⃣  Starting ingestion job..."
INGESTION_RESPONSE=$(aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}" \
  --no-cli-pager)

INGESTION_JOB_ID=$(echo "${INGESTION_RESPONSE}" | jq -r '.ingestionJob.ingestionJobId')
echo "   Job ID: ${INGESTION_JOB_ID}"

# Wait for ingestion
echo "   Waiting for ingestion to complete..."
for i in {1..60}; do
  JOB_STATUS=$(aws bedrock-agent get-ingestion-job \
    --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" \
    --ingestion-job-id "${INGESTION_JOB_ID}" \
    --no-cli-pager 2>/dev/null || echo "{}")

  STATUS=$(echo "${JOB_STATUS}" | jq -r '.ingestionJob.status // "UNKNOWN"')

  if [ "${STATUS}" = "COMPLETE" ]; then
    DOCS_SCANNED=$(echo "${JOB_STATUS}" | jq -r '.ingestionJob.statistics.numberOfDocumentsScanned // 0')
    DOCS_INDEXED=$(echo "${JOB_STATUS}" | jq -r '.ingestionJob.statistics.numberOfNewDocumentsIndexed // 0')
    echo "   ✓ Ingestion complete: ${DOCS_SCANNED} scanned, ${DOCS_INDEXED} indexed"
    break
  elif [ "${STATUS}" = "FAILED" ]; then
    echo "   ❌ Ingestion FAILED"
    exit 1
  fi

  if [ $((i % 10)) -eq 0 ]; then
    echo "   ⏳ Status: ${STATUS}"
  fi
  sleep 3
done

echo ""
echo "✅ Knowledge Base Created Successfully"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📚 KB ID: ${KB_ID}"
echo "📁 Data Bucket: ${DATA_BUCKET}"
echo "🗄️  Vector Bucket: ${VECTOR_BUCKET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
