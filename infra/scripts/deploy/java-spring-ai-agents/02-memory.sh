#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "SSM, Secrets Manager, and RDS read access"
init_context

DB_PARAMETER_NAME="workshop-db-connection-string"
DB_SECRET_ID="workshop-db-secret"
DB_CLUSTER_ID="workshop-db-cluster"

DB_URL=$(aws_cli ssm get-parameter --name "${DB_PARAMETER_NAME}" --query 'Parameter.Value' --output text)
[[ "${DB_URL}" == jdbc:postgresql://* ]] || die "${DB_PARAMETER_NAME} is not a PostgreSQL JDBC URL"
DB_SECRET_ARN=$(aws_cli secretsmanager describe-secret --secret-id "${DB_SECRET_ID}" --query ARN --output text)
DB_CLUSTER_ARN=$(aws_cli rds describe-db-clusters --db-cluster-identifier "${DB_CLUSTER_ID}" \
  --query 'DBClusters[0].DBClusterArn' --output text)
DB_STATUS=$(aws_cli rds describe-db-clusters --db-cluster-identifier "${DB_CLUSTER_ID}" \
  --query 'DBClusters[0].Status' --output text)
[[ "${DB_STATUS}" == "available" ]] || die "Aurora cluster ${DB_CLUSTER_ID} is not available: ${DB_STATUS}"

state_set DB_PARAMETER_NAME "${DB_PARAMETER_NAME}"
state_set DB_SECRET_ID "${DB_SECRET_ID}"
state_set DB_SECRET_ARN "${DB_SECRET_ARN}"
state_set DB_CLUSTER_ID "${DB_CLUSTER_ID}"
state_set DB_CLUSTER_ARN "${DB_CLUSTER_ARN}"
state_set DB_NAME "workshop"
state_set DB_URL "${DB_URL}"
log "Validated predeployed Aurora for JDBC conversation memory. No credentials were read or persisted."
