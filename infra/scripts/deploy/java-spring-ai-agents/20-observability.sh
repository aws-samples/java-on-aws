#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "Bedrock logging, CloudWatch Logs, S3, IAM, and SSM access"
init_context
require_workshop_role workshop-bedrock-logging-role

LOG_GROUP="/aws/bedrock/model-invocations"
if aws_cli logs describe-log-groups --log-group-name-prefix "${LOG_GROUP}" \
  --query "logGroups[?logGroupName=='${LOG_GROUP}'].logGroupName | [0]" --output text | grep -qx "${LOG_GROUP}"; then
  [[ -n "${BEDROCK_LOG_GROUP_CREATED:-}" ]] || state_set BEDROCK_LOG_GROUP_CREATED false
else
  aws_cli logs create-log-group --log-group-name "${LOG_GROUP}"
  state_set BEDROCK_LOG_GROUP_CREATED true
fi

WORKSHOP_BUCKET=$(aws_cli ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/workshop-bedrock-logging-role"
DESIRED=$(jq -nc --arg group "${LOG_GROUP}" --arg role "${ROLE_ARN}" --arg bucket "${WORKSHOP_BUCKET}" \
  '{loggingConfig:{cloudWatchConfig:{logGroupName:$group,roleArn:$role,largeDataDeliveryS3Config:{bucketName:$bucket,keyPrefix:"bedrock-logs"}},s3Config:{bucketName:$bucket,keyPrefix:"bedrock-logs"},textDataDeliveryEnabled:true,imageDataDeliveryEnabled:true,embeddingDataDeliveryEnabled:true}}')
CURRENT=$(aws_cli bedrock get-model-invocation-logging-configuration)
if [[ -z "${BEDROCK_LOGGING_ORIGINAL_B64:-}" ]]; then
  if [[ -n "${CURRENT}" && "$(jq -r '.loggingConfig // empty' <<<"${CURRENT}")" != "" ]]; then
    state_set BEDROCK_LOGGING_ORIGINAL_B64 "$(encode_b64 "$(jq -c '.loggingConfig' <<<"${CURRENT}")")"
  else
    state_set BEDROCK_LOGGING_ORIGINAL_B64 __NONE__
  fi
fi
if [[ "$(jq -S '.loggingConfig' <<<"${CURRENT:-{}}")" != "$(jq -S '.loggingConfig' <<<"${DESIRED}")" ]]; then
  config_file="${WORK_DIR}/bedrock-logging.json"
  printf '%s\n' "${DESIRED}" > "${config_file}"
  aws_cli bedrock put-model-invocation-logging-configuration --cli-input-json "file://${config_file}"
fi
state_set BEDROCK_LOG_GROUP "${LOG_GROUP}"
state_set BEDROCK_LOGGING_CONFIGURED true
log "Bedrock model invocation logging is configured idempotently for CloudWatch Logs and the workshop S3 bucket."
