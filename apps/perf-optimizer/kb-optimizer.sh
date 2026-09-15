#!/usr/bin/env bash
# ============================================================================
# kb-optimizer.sh — create the perf-optimizer Bedrock Knowledge Base (S3 Vectors)
# seeded with the right-sizing playbook + golden AOT/CRaC Dockerfiles, so the
# agent's artifacts are copy-paste-correct. Writes the KB id to SSM and grants
# the perf-analyzer pod role Retrieve. Run on the ide instance.
# Adapted from java-spring-ai-agents/scripts/03-knowledgebase.sh.
# ============================================================================
set -uo pipefail
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}
BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
DATA_BUCKET="perf-optimizer-kb-data-${ACCOUNT_ID}"
VECTOR_BUCKET="perf-optimizer-kb-vectors-${ACCOUNT_ID}"
INDEX="perf-optimizer-index"
KB_ROLE="perf-optimizer-kb-role"
KB_NAME="perf-optimizer-kb"
APP_ROLE="perf-analyzer-eks-pod-role"   # perf-optimizer reuses this SA/role
EMBED_ARN="arn:aws:bedrock:${AWS_REGION}::foundation-model/amazon.titan-embed-text-v2:0"
echo "acct=$ACCOUNT_ID region=$AWS_REGION"

# --- fetch KB docs from the module tarball in S3 ---
WORK=$HOME/perf-optimizer-src; rm -rf "$WORK"; mkdir -p "$WORK"
aws s3 cp "s3://${BUCKET}/perf-scenario/perf-optimizer.tgz" "$WORK/src.tgz" >/dev/null
tar -xzf "$WORK/src.tgz" -C "$WORK"
KB_DOCS="$WORK/perf-optimizer/kb"
ls "$KB_DOCS"/*.md >/dev/null || { echo "KB docs not found in module"; exit 1; }

echo "== S3 buckets + vector index =="
aws s3api head-bucket --bucket "$DATA_BUCKET" 2>/dev/null || aws s3api create-bucket --bucket "$DATA_BUCKET" --no-cli-pager >/dev/null
if ! aws s3vectors list-vector-buckets --query "vectorBuckets[?vectorBucketName=='${VECTOR_BUCKET}']" --output text 2>/dev/null | grep -q .; then
  aws s3vectors create-vector-bucket --vector-bucket-name "$VECTOR_BUCKET" --no-cli-pager
fi
if ! aws s3vectors list-indexes --vector-bucket-name "$VECTOR_BUCKET" --query "indexes[?indexName=='${INDEX}']" --output text 2>/dev/null | grep -q .; then
  aws s3vectors create-index --vector-bucket-name "$VECTOR_BUCKET" --index-name "$INDEX" \
    --data-type float32 --dimension 1024 --distance-metric cosine --no-cli-pager
fi

echo "== IAM role for the KB =="
if ! aws iam get-role --role-name "$KB_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$KB_ROLE" \
    --permissions-boundary "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" \
    --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"bedrock.amazonaws.com\"},\"Action\":\"sts:AssumeRole\",\"Condition\":{\"StringEquals\":{\"aws:SourceAccount\":\"${ACCOUNT_ID}\"}}}]}" --no-cli-pager >/dev/null
  aws iam put-role-policy --role-name "$KB_ROLE" --policy-name kb-policy \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::${DATA_BUCKET}\",\"arn:aws:s3:::${DATA_BUCKET}/*\"]},{\"Effect\":\"Allow\",\"Action\":[\"bedrock:InvokeModel\"],\"Resource\":[\"${EMBED_ARN}\"]},{\"Effect\":\"Allow\",\"Action\":[\"s3vectors:*\"],\"Resource\":[\"arn:aws:s3vectors:${AWS_REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}\",\"arn:aws:s3vectors:${AWS_REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}/*\"]}]}" --no-cli-pager >/dev/null
  echo -n "waiting for role propagation"; sleep 10; echo " done"
fi

echo "== Knowledge Base =="
KB_ID=$(aws bedrock-agent list-knowledge-bases --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null)
if [ "$KB_ID" = "None" ] || [ -z "$KB_ID" ]; then
  KB_ID=$(aws bedrock-agent create-knowledge-base --name "$KB_NAME" \
    --description "perf-optimizer: right-sizing playbook + golden AOT/CRaC Dockerfiles" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${KB_ROLE}" \
    --knowledge-base-configuration "{\"type\":\"VECTOR\",\"vectorKnowledgeBaseConfiguration\":{\"embeddingModelArn\":\"${EMBED_ARN}\"}}" \
    --storage-configuration "{\"type\":\"S3_VECTORS\",\"s3VectorsConfiguration\":{\"vectorBucketArn\":\"arn:aws:s3vectors:${AWS_REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}\",\"indexName\":\"${INDEX}\"}}" \
    --no-cli-pager --query 'knowledgeBase.knowledgeBaseId' --output text)
  echo -n "waiting for KB ACTIVE"
  while [ "$(aws bedrock-agent get-knowledge-base --knowledge-base-id "$KB_ID" --query 'knowledgeBase.status' --output text)" != "ACTIVE" ]; do echo -n "."; sleep 5; done; echo " ok"
fi
echo "KB_ID=$KB_ID"

echo "== data source + ingest =="
DS_ID=$(aws bedrock-agent list-data-sources --knowledge-base-id "$KB_ID" --query "dataSourceSummaries[?name=='optimizer-docs'].dataSourceId | [0]" --output text 2>/dev/null)
if [ "$DS_ID" = "None" ] || [ -z "$DS_ID" ]; then
  DS_ID=$(aws bedrock-agent create-data-source --knowledge-base-id "$KB_ID" --name "optimizer-docs" \
    --data-source-configuration "{\"type\":\"S3\",\"s3Configuration\":{\"bucketArn\":\"arn:aws:s3:::${DATA_BUCKET}\",\"inclusionPrefixes\":[\"docs/\"]}}" \
    --no-cli-pager --query 'dataSource.dataSourceId' --output text)
fi
aws s3 cp "$KB_DOCS/" "s3://${DATA_BUCKET}/docs/" --recursive --exclude "*" --include "*.md" >/dev/null
JOB_ID=$(aws bedrock-agent start-ingestion-job --knowledge-base-id "$KB_ID" --data-source-id "$DS_ID" --query 'ingestionJob.ingestionJobId' --output text)
echo -n "ingesting"
while [ "$(aws bedrock-agent get-ingestion-job --knowledge-base-id "$KB_ID" --data-source-id "$DS_ID" --ingestion-job-id "$JOB_ID" --query 'ingestionJob.status' --output text)" = "IN_PROGRESS" ]; do echo -n "."; sleep 5; done; echo " done"

echo "== publish KB id + grant Retrieve to $APP_ROLE =="
aws ssm put-parameter --name /perf-optimizer/kb-id --type String --value "$KB_ID" --overwrite --no-cli-pager >/dev/null
aws iam put-role-policy --role-name "$APP_ROLE" --policy-name perf-optimizer-kb-retrieve \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"bedrock:Retrieve\"],\"Resource\":[\"arn:aws:bedrock:${AWS_REGION}:${ACCOUNT_ID}:knowledge-base/${KB_ID}\"]}]}" --no-cli-pager >/dev/null \
  && echo "granted bedrock:Retrieve on KB to $APP_ROLE" || echo "WARN: could not attach Retrieve policy to $APP_ROLE (grant manually)"

echo
echo "KB ready: $KB_ID  (SSM /perf-optimizer/kb-id)"
echo "Now redeploy so the optimizer wires the KB advisor:  bash ~/deploy-optimizer.sh"
