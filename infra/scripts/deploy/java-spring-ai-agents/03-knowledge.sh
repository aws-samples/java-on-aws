#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "RDS Data API read access and Bedrock model access"
init_context
require_state DB_CLUSTER_ARN DB_SECRET_ARN DB_NAME

RESULT=$(aws_cli rds-data execute-statement --resource-arn "${DB_CLUSTER_ARN}" \
  --secret-arn "${DB_SECRET_ARN}" --database "${DB_NAME}" \
  --sql "SELECT extversion FROM pg_extension WHERE extname = 'vector'" --include-result-metadata)
PGVECTOR_VERSION=$(jq -r '.records[0][0].stringValue // empty' <<<"${RESULT}")
[[ -n "${PGVECTOR_VERSION}" ]] || die "The pgvector extension is not installed in the predeployed Aurora database"

state_set PGVECTOR_VERSION "${PGVECTOR_VERSION}"
state_set EMBEDDING_MODEL_ID "amazon.titan-embed-text-v2:0"
state_set EMBEDDING_DIMENSIONS "1024"
log "Validated PgVector ${PGVECTOR_VERSION} for Aurora/PgVector RAG."
