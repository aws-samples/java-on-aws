#!/bin/bash
# ============================================================
# test-kb.sh - Test Knowledge Base retrieval
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
KB_NAME="${APP_NAME}-kb"

KB_ID=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
  --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null || echo "")

if [ -z "${KB_ID}" ] || [ "${KB_ID}" = "None" ]; then
  echo "❌ Knowledge Base not found: ${KB_NAME}"
  exit 1
fi

echo "📚 Testing Knowledge Base: ${KB_ID}"
echo ""

QUERIES=(
  "What are our limits for Europe?"
  "What is the policy for alcohol in meals?"
)

for QUERY in "${QUERIES[@]}"; do
  echo "Query: ${QUERY}"
  echo ""

  RESPONSE=$(aws bedrock-agent-runtime retrieve \
    --knowledge-base-id "${KB_ID}" \
    --retrieval-query "{\"text\": \"${QUERY}\"}" \
    --region "${REGION}" \
    --no-cli-pager 2>&1)

  echo "Results:"
  echo "${RESPONSE}" | jq -r '.retrievalResults[] | "---\nScore: \(.score)\nSource: \(.location.s3Location.uri // "N/A")\nContent: \(.content.text[0:300])..."' 2>/dev/null || echo "${RESPONSE}"
  echo ""
  echo "=============================================="
  echo ""
done
