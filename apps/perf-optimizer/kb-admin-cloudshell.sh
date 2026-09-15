#!/usr/bin/env bash
# ============================================================================
# kb-admin-cloudshell.sh — provision the perf-optimizer Bedrock KB (S3 Vectors)
# from an ADMIN identity (e.g. AWS CloudShell), because participant identities
# and the workshop permissions boundary block it:
#   - WSParticipantRole / workshop-ide-user cannot s3:CreateBucket / iam:CreateRole / PassRole
#   - even when granted, the workshop permissions boundary on a SELF-created role
#     blocks s3vectors:QueryVectors, so CreateKnowledgeBase fails validation.
# This creates the KB role WITHOUT the boundary, builds the KB from the docs
# already in the workshop bucket, ingests, writes the KB id to SSM, and grants
# the app pod role Retrieve. For the real workshop this becomes a bootstrap/CDK
# step. Run in CloudShell (admin, us-east-1). Idempotent.
# ============================================================================
export AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DATA_BUCKET="perf-optimizer-kb-data-${ACCOUNT_ID}"
VECTOR_BUCKET="perf-optimizer-kb-vectors-${ACCOUNT_ID}"
INDEX="perf-optimizer-index"; KB_ROLE="perf-optimizer-kb-role"; KB_NAME="perf-optimizer-kb"
APP_ROLE="perf-analyzer-eks-pod-role"
EMBED_ARN="arn:aws:bedrock:${AWS_REGION}::foundation-model/amazon.titan-embed-text-v2:0"
WS_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text 2>/dev/null || echo "workshop-bucket-${ACCOUNT_ID}-us-east-1-20260826171103")
echo "acct=$ACCOUNT_ID  data=$DATA_BUCKET  ws=$WS_BUCKET"

# 1) data bucket + vector index (idempotent)
aws s3api head-bucket --bucket "$DATA_BUCKET" 2>/dev/null || aws s3api create-bucket --bucket "$DATA_BUCKET"
aws s3vectors list-vector-buckets --query "vectorBuckets[?vectorBucketName=='${VECTOR_BUCKET}']" --output text 2>/dev/null | grep -q . \
  || aws s3vectors create-vector-bucket --vector-bucket-name "$VECTOR_BUCKET"
aws s3vectors list-indexes --vector-bucket-name "$VECTOR_BUCKET" --query "indexes[?indexName=='${INDEX}']" --output text 2>/dev/null | grep -q . \
  || aws s3vectors create-index --vector-bucket-name "$VECTOR_BUCKET" --index-name "$INDEX" --data-type float32 --dimension 1024 --distance-metric cosine

# 2) KB role WITHOUT permissions boundary (recreate cleanly)
aws iam delete-role-policy --role-name "$KB_ROLE" --policy-name kb-policy 2>/dev/null || true
aws iam delete-role --role-name "$KB_ROLE" 2>/dev/null || true
aws iam create-role --role-name "$KB_ROLE" \
  --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"bedrock.amazonaws.com\"},\"Action\":\"sts:AssumeRole\",\"Condition\":{\"StringEquals\":{\"aws:SourceAccount\":\"${ACCOUNT_ID}\"}}}]}" >/dev/null
aws iam put-role-policy --role-name "$KB_ROLE" --policy-name kb-policy \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::${DATA_BUCKET}\",\"arn:aws:s3:::${DATA_BUCKET}/*\"]},{\"Effect\":\"Allow\",\"Action\":[\"bedrock:InvokeModel\"],\"Resource\":[\"${EMBED_ARN}\"]},{\"Effect\":\"Allow\",\"Action\":[\"s3vectors:*\"],\"Resource\":[\"arn:aws:s3vectors:${AWS_REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}\",\"arn:aws:s3vectors:${AWS_REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}/*\"]}]}" >/dev/null
echo "role created; waiting for propagation"; sleep 15

# 3) KB docs from the workshop bucket -> data bucket
cd /tmp && rm -rf kbwork && mkdir kbwork && cd kbwork
aws s3 cp "s3://${WS_BUCKET}/perf-scenario/perf-optimizer.tgz" src.tgz && tar -xzf src.tgz
aws s3 cp perf-optimizer/kb/ "s3://${DATA_BUCKET}/docs/" --recursive --exclude "*" --include "*.md"

# 4) create KB (retry while the role propagates)
KB_ID=$(aws bedrock-agent list-knowledge-bases --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null)
if [ "$KB_ID" = "None" ] || [ -z "$KB_ID" ]; then
  for i in 1 2 3 4 5 6; do
    KB_ID=$(aws bedrock-agent create-knowledge-base --name "$KB_NAME" \
      --description "perf-optimizer: right-sizing playbook + golden AOT/CRaC Dockerfiles" \
      --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${KB_ROLE}" \
      --knowledge-base-configuration "{\"type\":\"VECTOR\",\"vectorKnowledgeBaseConfiguration\":{\"embeddingModelArn\":\"${EMBED_ARN}\"}}" \
      --storage-configuration "{\"type\":\"S3_VECTORS\",\"s3VectorsConfiguration\":{\"vectorBucketArn\":\"arn:aws:s3vectors:${AWS_REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}\",\"indexName\":\"${INDEX}\"}}" \
      --query 'knowledgeBase.knowledgeBaseId' --output text 2>/tmp/kberr) && break
    echo "  create attempt $i failed, retrying in 10s..."; sed 's/^/    /' /tmp/kberr; sleep 10
  done
fi
echo "KB_ID=$KB_ID"
until [ "$(aws bedrock-agent get-knowledge-base --knowledge-base-id "$KB_ID" --query 'knowledgeBase.status' --output text 2>/dev/null)" = "ACTIVE" ]; do echo -n "."; sleep 5; done; echo " ACTIVE"

# 5) data source + ingest
DS_ID=$(aws bedrock-agent list-data-sources --knowledge-base-id "$KB_ID" --query "dataSourceSummaries[?name=='optimizer-docs'].dataSourceId | [0]" --output text 2>/dev/null)
if [ "$DS_ID" = "None" ] || [ -z "$DS_ID" ]; then
  DS_ID=$(aws bedrock-agent create-data-source --knowledge-base-id "$KB_ID" --name optimizer-docs \
    --data-source-configuration "{\"type\":\"S3\",\"s3Configuration\":{\"bucketArn\":\"arn:aws:s3:::${DATA_BUCKET}\",\"inclusionPrefixes\":[\"docs/\"]}}" \
    --query 'dataSource.dataSourceId' --output text)
fi
JOB_ID=$(aws bedrock-agent start-ingestion-job --knowledge-base-id "$KB_ID" --data-source-id "$DS_ID" --query 'ingestionJob.ingestionJobId' --output text)
until [ "$(aws bedrock-agent get-ingestion-job --knowledge-base-id "$KB_ID" --data-source-id "$DS_ID" --ingestion-job-id "$JOB_ID" --query 'ingestionJob.status' --output text)" != "IN_PROGRESS" ]; do echo -n "."; sleep 5; done; echo " ingested"

# 6) publish id + grant Retrieve to the app pod role
aws ssm put-parameter --name /perf-optimizer/kb-id --type String --value "$KB_ID" --overwrite >/dev/null
aws iam put-role-policy --role-name "$APP_ROLE" --policy-name perf-optimizer-kb-retrieve \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"bedrock:Retrieve\"],\"Resource\":[\"arn:aws:bedrock:${AWS_REGION}:${ACCOUNT_ID}:knowledge-base/${KB_ID}\"]}]}" >/dev/null
echo; echo "DONE. KB_ID=$KB_ID  (SSM /perf-optimizer/kb-id)"
echo "Next, on the ide instance:  bash ~/deploy-optimizer.sh   (then re-run the MCP call)"
