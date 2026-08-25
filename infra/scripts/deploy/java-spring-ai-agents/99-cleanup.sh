#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

APPLY=false
case "${1:-}" in
  "") ;;
  --apply) APPLY=true; shift ;;
  -h|--help) echo "Usage: 99-cleanup.sh [--apply]"; exit 0 ;;
  *) die "Usage: 99-cleanup.sh [--apply]" ;;
esac
(($# == 0)) || die "Usage: 99-cleanup.sh [--apply]"
print_prerequisites "AWS access and kubectl for EKS resources"
init_context_read_only
load_state

print_plan() {
  cat <<EOF
Cleanup plan for account ${ACCOUNT_ID}, Region ${AWS_REGION}:
- Restore or remove the deployed AI-agent target resources tracked in ${STATE_FILE}.
- Remove suite-owned EKS AI-agent and MCP manifests; namespaces and Pod Identity associations only when the suite created them.
- Restore the precreated ECS service configuration; never delete the ECS service or cluster.
- Restore a preexisting Lambda from its published backup, or delete the function only if this suite created it.
- Delete only the suite-specific AgentCore Runtime/UI resources tracked as suite-created.
- Remove the deterministic sample Unicorn only if this suite created it.
- Restore existing Cognito client settings/users, or delete the pool only if this suite created it.
- Restore the previous Bedrock model invocation logging configuration.
- Remove the suite Lambda object, but never delete the workshop bucket.

Never deleted: prerequisite CloudFormation stack, VPC, Aurora, EKS cluster, ECS service,
IAM roles, workshop bucket, ECR repositories, or participant source directories.
EOF
}

print_plan
if [[ "${APPLY}" != true ]]; then
  log "Plan only. Re-run with --apply to perform these ownership-scoped actions."
  exit 0
fi
if [[ ! -f "${STATE_FILE}" ]]; then
  log "No suite state file exists; there are no tracked resources to clean up."
  exit 0
fi
secure_work_dir
cleanup_failures=()
record_failure() {
  cleanup_failures+=("$1")
  warn "$1"
}

AWS_PROBE_OUTPUT=""
probe_aws_resource() {
  AWS_PROBE_OUTPUT=""
  if AWS_PROBE_OUTPUT=$("$@" 2>&1); then
    return 0
  fi
  if grep -Eqi 'ResourceNotFoundException|NotFoundException|NoSuch[A-Za-z]+|InvalidGroup\.NotFound|UserNotFoundException|\(404\)|status code: 404|does not exist' <<<"${AWS_PROBE_OUTPUT}"; then
    return 1
  fi
  return 2
}

probe_aws_resource_with_retry() {
  local attempts="$1" interval="$2" i probe_status
  shift 2
  for ((i=1; i<=attempts; i++)); do
    probe_status=0
    probe_aws_resource "$@" || probe_status=$?
    [[ "${probe_status}" != 2 ]] && return "${probe_status}"
    ((i == attempts)) || sleep "${interval}"
  done
  return 2
}

KUBECTL_PROBE_OUTPUT=""
probe_k8s_resource() {
  local kind="$1" name="$2" namespace="${3:-}"
  local namespace_args=()
  [[ -z "${namespace}" ]] || namespace_args=(-n "${namespace}")
  KUBECTL_PROBE_OUTPUT=""
  if KUBECTL_PROBE_OUTPUT=$(kubectl get "${kind}" "${name}" "${namespace_args[@]}" -o json 2>&1); then
    return 0
  fi
  if grep -Eq '^Error from server \(NotFound\):' <<<"${KUBECTL_PROBE_OUTPUT}"; then
    return 1
  fi
  return 2
}
if [[ -n "${EKS_NAMESPACE_CREATED:-}${EKS_SERVICE_ACCOUNT_CREATED:-}${EKS_POD_IDENTITY_ID:-}${EKS_SPC_BACKUP_PATH:-}${EKS_DEPLOYMENT_BACKUP_PATH:-}${EKS_SERVICE_BACKUP_PATH:-}${EKS_INGRESS_BACKUP_PATH:-}${MCP_NAMESPACE_CREATED:-}${MCP_SERVICE_ACCOUNT_CREATED:-}${MCP_POD_IDENTITY_ID:-}${MCP_SPC_BACKUP_PATH:-}${MCP_DEPLOYMENT_BACKUP_PATH:-}${MCP_SERVICE_BACKUP_PATH:-}${MCP_INGRESS_BACKUP_PATH:-}" ]]; then
  ensure_eks_context
fi
log "Applying cleanup plan"

restore_pod_identity() {
  local prefix="$1" created_var="${1}_POD_IDENTITY_CREATED" id_var="${1}_POD_IDENTITY_ID" role_var="${1}_ORIGINAL_POD_ROLE_ARN"
  local association_id="${!id_var:-}" created="${!created_var:-false}" original_role="${!role_var:-}"
  [[ -n "${association_id}" ]] || return 0
  if [[ "${created}" == true ]]; then
    aws_cli eks delete-pod-identity-association --cluster-name "${CLUSTER_NAME}" --association-id "${association_id}" >/dev/null 2>&1 || \
      record_failure "Could not delete suite-owned ${prefix} Pod Identity association ${association_id}"
  elif [[ -n "${original_role}" ]]; then
    aws_cli eks update-pod-identity-association --cluster-name "${CLUSTER_NAME}" --association-id "${association_id}" \
      --role-arn "${original_role}" >/dev/null 2>&1 || \
      record_failure "Could not restore ${prefix} Pod Identity association ${association_id} to ${original_role}"
  fi
}

delete_k8s_app() {
  local namespace="$1" prefix="$2" service_account="$3" namespace_status
  command -v kubectl >/dev/null 2>&1 || { record_failure "kubectl unavailable; could not clean up ${namespace} resources"; return; }
  namespace_status=0
  probe_k8s_resource namespace "${namespace}" || namespace_status=$?
  case "${namespace_status}" in
    0) ;;
    1) return 0 ;;
    *) record_failure "Could not read namespace ${namespace} before cleanup: ${KUBECTL_PROBE_OUTPUT}"; return ;;
  esac
  kubectl delete ingress,service,deployment -n "${namespace}" -l "app.kubernetes.io/managed-by=${SUITE_OWNER}" \
    --ignore-not-found --wait=true --timeout=180s >/dev/null || \
    record_failure "Could not delete all suite-owned workload resources in namespace ${namespace}"
  kubectl delete secretproviderclass -n "${namespace}" -l "app.kubernetes.io/managed-by=${SUITE_OWNER}" \
    --ignore-not-found --wait=true --timeout=120s >/dev/null || \
    record_failure "Could not delete all suite-owned SecretProviderClass resources in namespace ${namespace}"

  local backup_var backup_path
  for backup_var in "${prefix}_SPC_BACKUP_PATH" "${prefix}_DEPLOYMENT_BACKUP_PATH" "${prefix}_SERVICE_BACKUP_PATH" "${prefix}_INGRESS_BACKUP_PATH"; do
    backup_path="${!backup_var:-}"
    if [[ -n "${backup_path}" ]]; then
      if [[ -f "${backup_path}" ]]; then
        kubectl apply -f "${backup_path}" >/dev/null || record_failure "Could not restore Kubernetes backup ${backup_path}"
      else
        record_failure "Kubernetes restore snapshot is missing: ${backup_path}"
      fi
    fi
  done

  local sa_created_var="${prefix}_SERVICE_ACCOUNT_CREATED" namespace_created_var="${prefix}_NAMESPACE_CREATED"
  if [[ "${!sa_created_var:-false}" == true ]]; then
    kubectl delete serviceaccount "${service_account}" -n "${namespace}" --ignore-not-found --wait=true --timeout=60s >/dev/null || \
      record_failure "Could not delete suite-owned service account ${namespace}/${service_account}"
  fi
  if [[ "${!namespace_created_var:-false}" == true ]]; then
    kubectl delete namespace "${namespace}" --ignore-not-found --wait=true --timeout=180s >/dev/null || \
      record_failure "Could not delete suite-owned namespace ${namespace}"
  fi
}

# AgentCore UI and Runtime
if [[ -n "${AGENTCORE_DISTRIBUTION_ID:-}" && "${AGENTCORE_DISTRIBUTION_CREATED:-false}" == true ]] && \
  aws_cli cloudfront get-distribution --id "${AGENTCORE_DISTRIBUTION_ID}" >/dev/null 2>&1; then
  cf_file=$(mktemp "${WORK_DIR}/cf-delete.XXXXXX")
  aws_cli cloudfront get-distribution-config --id "${AGENTCORE_DISTRIBUTION_ID}" > "${cf_file}"
  etag=$(jq -r .ETag "${cf_file}")
  if [[ "$(jq -r .DistributionConfig.Enabled "${cf_file}")" == true ]]; then
    jq '.DistributionConfig | .Enabled=false' "${cf_file}" > "${cf_file}.disabled"
    aws_cli cloudfront update-distribution --id "${AGENTCORE_DISTRIBUTION_ID}" --if-match "${etag}" \
      --distribution-config "file://${cf_file}.disabled" >/dev/null
  fi
  status=""
  for i in {1..80}; do
    status=$(aws_cli cloudfront get-distribution --id "${AGENTCORE_DISTRIBUTION_ID}" --query Distribution.Status --output text 2>/dev/null || true)
    [[ "${status}" == Deployed ]] && break
    ((i == 80)) || sleep 15
  done
  [[ "${status}" == Deployed ]] || die "CloudFront distribution did not become deletable"
  etag=$(aws_cli cloudfront get-distribution-config --id "${AGENTCORE_DISTRIBUTION_ID}" --query ETag --output text)
  aws_cli cloudfront delete-distribution --id "${AGENTCORE_DISTRIBUTION_ID}" --if-match "${etag}"
  rm -f "${cf_file}" "${cf_file}.disabled"
fi

if [[ -n "${AGENTCORE_RUNTIME_ID:-}" && "${AGENTCORE_RUNTIME_CREATED:-false}" == true ]]; then
  aws_cli bedrock-agentcore-control delete-agent-runtime --agent-runtime-id "${AGENTCORE_RUNTIME_ID}" >/dev/null
fi
if [[ -n "${AGENTCORE_LOG_GROUP:-}" ]]; then
  if aws_cli logs describe-log-groups --log-group-name-prefix "${AGENTCORE_LOG_GROUP}" \
    --query "logGroups[?logGroupName=='${AGENTCORE_LOG_GROUP}'].logGroupName | [0]" --output text | grep -qx "${AGENTCORE_LOG_GROUP}"; then
    aws_cli logs delete-log-group --log-group-name "${AGENTCORE_LOG_GROUP}" >/dev/null 2>&1 || \
      record_failure "Could not delete suite-owned AgentCore log group ${AGENTCORE_LOG_GROUP}"
  fi
fi

if [[ -n "${AGENTCORE_UI_BUCKET:-}" && "${AGENTCORE_UI_BUCKET_CREATED:-false}" == true ]]; then
  aws_cli s3 rm "s3://${AGENTCORE_UI_BUCKET}" --recursive --only-show-errors || \
    record_failure "Could not empty suite-owned AgentCore UI bucket ${AGENTCORE_UI_BUCKET}"
  aws_cli s3api delete-bucket --bucket "${AGENTCORE_UI_BUCKET}" || \
    record_failure "Could not delete suite-owned AgentCore UI bucket ${AGENTCORE_UI_BUCKET}"
fi
if [[ -n "${AGENTCORE_OAI_ID:-}" && "${AGENTCORE_OAI_CREATED:-false}" == true ]]; then
  if oai_etag=$(aws_cli cloudfront get-cloud-front-origin-access-identity-config --id "${AGENTCORE_OAI_ID}" --query ETag --output text 2>/dev/null); then
    aws_cli cloudfront delete-cloud-front-origin-access-identity --id "${AGENTCORE_OAI_ID}" --if-match "${oai_etag}" || \
      record_failure "Could not delete suite-owned CloudFront OAI ${AGENTCORE_OAI_ID}"
  fi
fi

# Lambda restore/delete, URL permissions, package, and suite-created security group.
lambda_cleanup_status=1
lambda_function_tracked=false
if [[ -n "${LAMBDA_CREATED:-}${LAMBDA_BACKUP_VERSION:-}${LAMBDA_URL_CREATED:-}${LAMBDA_URL_ORIGINAL_B64:-}${LAMBDA_PERMISSION_URL_CREATED:-}${LAMBDA_PERMISSION_INVOKE_CREATED:-}" ]]; then
  lambda_function_tracked=true
  lambda_cleanup_status=0
  probe_aws_resource_with_retry 5 5 aws_cli lambda get-function-configuration --function-name aiagent || lambda_cleanup_status=$?
  if [[ "${lambda_cleanup_status}" == 2 ]]; then
    record_failure "Could not read tracked Lambda function aiagent before cleanup: ${AWS_PROBE_OUTPUT}"
  elif [[ "${lambda_cleanup_status}" == 1 && "${LAMBDA_CREATED:-false}" != true ]]; then
    record_failure "Tracked pre-existing Lambda function aiagent was not found; restore state was preserved"
  fi
fi
if [[ "${lambda_cleanup_status}" == 0 ]]; then
  if [[ "${LAMBDA_CREATED:-false}" == true ]]; then
    aws_cli lambda delete-function --function-name aiagent
  elif [[ -n "${LAMBDA_BACKUP_VERSION:-}" ]]; then
    restore_dir=$(mktemp -d "${WORK_DIR}/lambda-restore.XXXXXX")
    chmod 700 "${restore_dir}"
    code_url=$(aws_cli lambda get-function --function-name aiagent --qualifier "${LAMBDA_BACKUP_VERSION}" --query Code.Location --output text)
    curl --fail-with-body -sS --max-time 300 "${code_url}" -o "${restore_dir}/backup.zip"
    chmod 600 "${restore_dir}/backup.zip"
    workshop_bucket=$(aws_cli ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
    restore_key="lambda/aiagent-suite-restore.zip"
    aws_cli s3 cp "${restore_dir}/backup.zip" "s3://${workshop_bucket}/${restore_key}" --only-show-errors
    aws_cli lambda update-function-code --function-name aiagent --s3-bucket "${workshop_bucket}" --s3-key "${restore_key}" >/dev/null
    aws_cli lambda wait function-updated-v2 --function-name aiagent
    backup=$(aws_cli lambda get-function-configuration --function-name aiagent --qualifier "${LAMBDA_BACKUP_VERSION}")
    jq '{FunctionName:.FunctionName,Role:.Role,Handler:.Handler,Description:.Description,Timeout:.Timeout,MemorySize:.MemorySize,Runtime:.Runtime,Environment:{Variables:(.Environment.Variables // {})},VpcConfig:{SubnetIds:(.VpcConfig.SubnetIds // []),SecurityGroupIds:(.VpcConfig.SecurityGroupIds // []),Ipv6AllowedForDualStack:(.VpcConfig.Ipv6AllowedForDualStack // false)},DeadLetterConfig:{TargetArn:(.DeadLetterConfig.TargetArn // "")},KMSKeyArn:(.KMSKeyArn // ""),TracingConfig:{Mode:(.TracingConfig.Mode // "PassThrough")},Layers:[.Layers[]?.Arn],EphemeralStorage:{Size:(.EphemeralStorage.Size // 512)},SnapStart:{ApplyOn:(.SnapStart.ApplyOn // "None")},LoggingConfig:.LoggingConfig}' <<<"${backup}" > "${restore_dir}/config.json"
    chmod 600 "${restore_dir}/config.json"
    aws_cli lambda update-function-configuration --cli-input-json "file://${restore_dir}/config.json" >/dev/null
    aws_cli lambda wait function-updated-v2 --function-name aiagent
    current_lambda=$(aws_cli lambda get-function-configuration --function-name aiagent)
    expected_lambda=$(jq -S '{CodeSha256,Role,Handler,Description,Timeout,MemorySize,Runtime,Environment:(.Environment.Variables // {}),VpcConfig:{SubnetIds:(.VpcConfig.SubnetIds // []),SecurityGroupIds:(.VpcConfig.SecurityGroupIds // []),Ipv6AllowedForDualStack:(.VpcConfig.Ipv6AllowedForDualStack // false)},DeadLetterConfig:(.DeadLetterConfig.TargetArn // ""),KMSKeyArn:(.KMSKeyArn // ""),TracingConfig:(.TracingConfig.Mode // "PassThrough"),Layers:[.Layers[]?.Arn],EphemeralStorage:(.EphemeralStorage.Size // 512),SnapStart:(.SnapStart.ApplyOn // "None"),LoggingConfig}' <<<"${backup}")
    actual_lambda=$(jq -S '{CodeSha256,Role,Handler,Description,Timeout,MemorySize,Runtime,Environment:(.Environment.Variables // {}),VpcConfig:{SubnetIds:(.VpcConfig.SubnetIds // []),SecurityGroupIds:(.VpcConfig.SecurityGroupIds // []),Ipv6AllowedForDualStack:(.VpcConfig.Ipv6AllowedForDualStack // false)},DeadLetterConfig:(.DeadLetterConfig.TargetArn // ""),KMSKeyArn:(.KMSKeyArn // ""),TracingConfig:(.TracingConfig.Mode // "PassThrough"),Layers:[.Layers[]?.Arn],EphemeralStorage:(.EphemeralStorage.Size // 512),SnapStart:(.SnapStart.ApplyOn // "None"),LoggingConfig}' <<<"${current_lambda}")
    aws_cli s3 rm "s3://${workshop_bucket}/${restore_key}" --only-show-errors
    rm -rf "${restore_dir}"
    if [[ "${actual_lambda}" == "${expected_lambda}" ]]; then
      if aws_cli lambda delete-function --function-name aiagent --qualifier "${LAMBDA_BACKUP_VERSION}" >/dev/null; then
        state_unset LAMBDA_BACKUP_VERSION
      else
        record_failure "Lambda was restored, but backup version ${LAMBDA_BACKUP_VERSION} could not be deleted"
      fi
    else
      record_failure "Lambda aiagent did not match backup version ${LAMBDA_BACKUP_VERSION} after restore; backup version and state were preserved"
    fi
  fi
fi
if [[ "${LAMBDA_CREATED:-false}" != true && "${lambda_cleanup_status}" == 0 ]]; then
  if [[ "${LAMBDA_URL_CREATED:-false}" == true ]]; then
    aws_cli lambda delete-function-url-config --function-name aiagent >/dev/null 2>&1 || \
      record_failure "Could not delete suite-created Lambda function URL configuration"
  elif [[ -n "${LAMBDA_URL_ORIGINAL_B64:-}" ]]; then
    original_url=$(decode_b64 "${LAMBDA_URL_ORIGINAL_B64}")
    jq --arg name aiagent '. + {FunctionName:$name}' <<<"${original_url}" > "${WORK_DIR}/lambda-url-restore.json"
    chmod 600 "${WORK_DIR}/lambda-url-restore.json"
    aws_cli lambda update-function-url-config --cli-input-json "file://${WORK_DIR}/lambda-url-restore.json" >/dev/null || \
      record_failure "Could not restore the original Lambda function URL configuration"
  fi
  if [[ "${LAMBDA_PERMISSION_URL_CREATED:-false}" == true ]]; then
    aws_cli lambda remove-permission --function-name aiagent --statement-id FunctionURLAllowPublicAccess >/dev/null 2>&1 || \
      record_failure "Could not remove suite-created Lambda permission FunctionURLAllowPublicAccess"
  fi
  if [[ "${LAMBDA_PERMISSION_INVOKE_CREATED:-false}" == true ]]; then
    aws_cli lambda remove-permission --function-name aiagent --statement-id FunctionURLPublicInvoke >/dev/null 2>&1 || \
      record_failure "Could not remove suite-created Lambda permission FunctionURLPublicInvoke"
  fi
fi
if [[ "${LAMBDA_PACKAGE_UPLOADED:-false}" == true && -n "${LAMBDA_S3_KEY:-}" ]]; then
  workshop_bucket=$(aws_cli ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
  if [[ "${LAMBDA_PACKAGE_PREEXISTED:-false}" == true && -n "${LAMBDA_PACKAGE_BACKUP_KEY:-}" ]]; then
    aws_cli s3api copy-object --bucket "${workshop_bucket}" --key "${LAMBDA_S3_KEY}" \
      --copy-source "${workshop_bucket}/${LAMBDA_PACKAGE_BACKUP_KEY}" >/dev/null
    aws_cli s3 rm "s3://${workshop_bucket}/${LAMBDA_PACKAGE_BACKUP_KEY}" --only-show-errors
  else
    aws_cli s3 rm "s3://${workshop_bucket}/${LAMBDA_S3_KEY}" --only-show-errors
  fi
fi
if [[ "${LAMBDA_SG_CREATED:-false}" == true && -n "${LAMBDA_SG_ID:-}" ]]; then
  sg_deleted=false
  for i in {1..20}; do
    if aws_cli ec2 delete-security-group --group-id "${LAMBDA_SG_ID}" >/dev/null 2>&1; then
      sg_deleted=true
      break
    fi
    ((i == 20)) || sleep 15
  done
  [[ "${sg_deleted}" == true ]] || record_failure "Could not delete suite-owned Lambda security group ${LAMBDA_SG_ID}"
fi

# Restore the precreated ECS service rather than deleting it.
if [[ -n "${ECS_SERVICE_ARN:-}" ]]; then
  ecs_snapshot_path="${ECS_ORIGINAL_PRIMARY_CONTAINER_PATH:-}"
  if [[ -z "${ecs_snapshot_path}" && -n "${ECS_ORIGINAL_PRIMARY_CONTAINER_B64:-}" ]]; then
    ecs_backup_dir="${WORK_DIR}/ecs-backups"
    mkdir -p "${ecs_backup_dir}"
    chmod 700 "${ecs_backup_dir}"
    ecs_snapshot_path="${ecs_backup_dir}/original-primary-container.json"
    decode_b64 "${ECS_ORIGINAL_PRIMARY_CONTAINER_B64}" > "${ecs_snapshot_path}"
    chmod 600 "${ecs_snapshot_path}"
    state_set ECS_ORIGINAL_PRIMARY_CONTAINER_PATH "${ecs_snapshot_path}"
    state_unset ECS_ORIGINAL_PRIMARY_CONTAINER_B64
  fi
  if [[ -n "${ecs_snapshot_path}" && -f "${ecs_snapshot_path}" ]]; then
    aws_cli ecs update-express-gateway-service --service-arn "${ECS_SERVICE_ARN}" \
      --primary-container "$(jq -c . "${ecs_snapshot_path}")" >/dev/null || \
      record_failure "Could not restore the ECS Express primary container from ${ecs_snapshot_path}"
    if [[ -n "${ECS_ORIGINAL_DEPLOYMENT_CONFIG_B64:-}" ]]; then
      aws_cli ecs update-service --cluster aiagent --service aiagent \
        --deployment-configuration "$(decode_b64 "${ECS_ORIGINAL_DEPLOYMENT_CONFIG_B64}")" >/dev/null || \
        record_failure "Could not restore the ECS deployment configuration"
    fi
  else
    record_failure "ECS restore snapshot is missing: ${ecs_snapshot_path:-not recorded}"
  fi
fi

# EKS AI-agent resources.
if [[ -n "${EKS_NAMESPACE_CREATED:-}${EKS_SERVICE_ACCOUNT_CREATED:-}${EKS_POD_IDENTITY_ID:-}${EKS_SPC_BACKUP_PATH:-}${EKS_DEPLOYMENT_BACKUP_PATH:-}${EKS_SERVICE_BACKUP_PATH:-}${EKS_INGRESS_BACKUP_PATH:-}" ]]; then
  restore_pod_identity EKS
  delete_k8s_app aiagent EKS aiagent
fi

# Deterministic sample first, then MCP EKS resources.
if [[ "${MCP_SAMPLE_CREATED:-false}" == true && -n "${MCP_SAMPLE_ID:-}" && -n "${MCP_URL:-}" ]]; then
  if curl --fail-with-body -sS --connect-timeout 10 --max-time 30 -X DELETE "${MCP_URL}/unicorns/${MCP_SAMPLE_ID}" >/dev/null; then
    sample_status=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
      "${MCP_URL}/unicorns/${MCP_SAMPLE_ID}" || true)
    [[ "${sample_status}" == 404 ]] || record_failure "Suite sample Unicorn ${MCP_SAMPLE_ID} is still retrievable after deletion (HTTP ${sample_status:-000})"
  else
    record_failure "Could not delete suite sample Unicorn ${MCP_SAMPLE_ID}"
  fi
fi
if [[ -n "${MCP_NAMESPACE_CREATED:-}${MCP_SERVICE_ACCOUNT_CREATED:-}${MCP_POD_IDENTITY_ID:-}${MCP_SPC_BACKUP_PATH:-}${MCP_DEPLOYMENT_BACKUP_PATH:-}${MCP_SERVICE_BACKUP_PATH:-}${MCP_INGRESS_BACKUP_PATH:-}" ]]; then
  restore_pod_identity MCP
  delete_k8s_app mcpserver MCP mcpserver
fi

# Cognito ownership-aware cleanup.
if [[ -n "${COGNITO_USER_POOL_ID:-}" ]]; then
  if [[ "${COGNITO_POOL_CREATED:-false}" == true ]]; then
    aws_cli cognito-idp delete-user-pool --user-pool-id "${COGNITO_USER_POOL_ID}" >/dev/null 2>&1 || \
      record_failure "Could not delete suite-owned Cognito user pool ${COGNITO_USER_POOL_ID}"
  else
    IFS=',' read -r -a created_users <<<"${COGNITO_CREATED_USERS:-}"
    for user in "${created_users[@]}"; do
      if [[ -n "${user}" ]]; then
        aws_cli cognito-idp admin-delete-user --user-pool-id "${COGNITO_USER_POOL_ID}" --username "${user}" >/dev/null 2>&1 || \
          record_failure "Could not delete suite-created Cognito user ${user}"
      fi
    done
    if [[ "${COGNITO_CLIENT_CREATED:-false}" == true && -n "${COGNITO_CLIENT_ID:-}" ]]; then
      aws_cli cognito-idp delete-user-pool-client --user-pool-id "${COGNITO_USER_POOL_ID}" --client-id "${COGNITO_CLIENT_ID}" >/dev/null 2>&1 || \
        record_failure "Could not delete suite-created Cognito client ${COGNITO_CLIENT_ID}"
    elif [[ -n "${COGNITO_CLIENT_ORIGINAL_CONFIG_B64:-}" ]]; then
      original_client=$(decode_b64 "${COGNITO_CLIENT_ORIGINAL_CONFIG_B64}")
      aws_cli cognito-idp update-user-pool-client --cli-input-json "${original_client}" >/dev/null || \
        record_failure "Could not restore Cognito client ${COGNITO_CLIENT_ID}"
    fi
  fi
fi

# Restore account-level Bedrock logging, then remove only a suite-created log group.
if [[ -n "${BEDROCK_LOGGING_ORIGINAL_B64:-}" ]]; then
  if [[ "${BEDROCK_LOGGING_ORIGINAL_B64}" == __NONE__ ]]; then
    aws_cli bedrock delete-model-invocation-logging-configuration >/dev/null 2>&1 || \
      record_failure "Could not remove the suite-applied Bedrock model invocation logging configuration"
  else
    jq -n --argjson config "$(decode_b64 "${BEDROCK_LOGGING_ORIGINAL_B64}")" '{loggingConfig:$config}' > "${WORK_DIR}/bedrock-logging-restore.json"
    chmod 600 "${WORK_DIR}/bedrock-logging-restore.json"
    aws_cli bedrock put-model-invocation-logging-configuration \
      --cli-input-json "file://${WORK_DIR}/bedrock-logging-restore.json" >/dev/null || \
      record_failure "Could not restore the original Bedrock model invocation logging configuration"
  fi
fi
if [[ "${BEDROCK_LOG_GROUP_CREATED:-false}" == true && -n "${BEDROCK_LOG_GROUP:-}" ]]; then
  aws_cli logs delete-log-group --log-group-name "${BEDROCK_LOG_GROUP}" >/dev/null 2>&1 || \
    record_failure "Could not delete suite-owned Bedrock log group ${BEDROCK_LOG_GROUP}"
fi

verify_aws_absent() {
  local description="$1"
  shift
  local error_file
  error_file=$(mktemp "${WORK_DIR}/verify-aws.XXXXXX")
  chmod 600 "${error_file}"
  if "$@" >/dev/null 2>"${error_file}"; then
    record_failure "Verification failed: ${description} still exists"
  elif ! grep -Eqi 'ResourceNotFoundException|NotFoundException|NoSuch[A-Za-z]+|InvalidGroup\.NotFound|UserNotFoundException|\(404\)|status code: 404|does not exist' "${error_file}"; then
    record_failure "Verification failed for ${description}: $(tr '\n' ' ' < "${error_file}")"
  fi
  rm -f "${error_file}"
}

verify_log_group_absent() {
  local log_group="$1" description="$2" result
  if ! result=$(aws_cli logs describe-log-groups --log-group-name-prefix "${log_group}" \
    --query "logGroups[?logGroupName=='${log_group}'].logGroupName | [0]" --output text 2>&1); then
    record_failure "Verification failed for ${description}: ${result}"
  elif [[ "${result}" == "${log_group}" ]]; then
    record_failure "Verification failed: ${description} still exists"
  fi
}

verify_pod_identity() {
  local prefix="$1" created_var="${1}_POD_IDENTITY_CREATED" id_var="${1}_POD_IDENTITY_ID" role_var="${1}_ORIGINAL_POD_ROLE_ARN"
  local association_id="${!id_var:-}" original_role="${!role_var:-}"
  [[ -n "${association_id}" ]] || return 0
  if [[ "${!created_var:-false}" == true ]]; then
    verify_aws_absent "suite-owned ${prefix} Pod Identity association ${association_id}" \
      aws_cli eks describe-pod-identity-association --cluster-name "${CLUSTER_NAME}" --association-id "${association_id}"
  elif [[ -n "${original_role}" ]]; then
    restored_role=$(aws_cli eks describe-pod-identity-association --cluster-name "${CLUSTER_NAME}" \
      --association-id "${association_id}" --query association.roleArn --output text 2>/dev/null || true)
    [[ "${restored_role}" == "${original_role}" ]] || \
      record_failure "Verification failed: ${prefix} Pod Identity role is ${restored_role:-unavailable}, expected ${original_role}"
  fi
}

verify_k8s_app() {
  local namespace="$1" prefix="$2" service_account="$3"
  local namespace_created_var="${prefix}_NAMESPACE_CREATED" sa_created_var="${prefix}_SERVICE_ACCOUNT_CREATED"
  local probe_status kind name backup_var backup_path expected_json actual_json

  probe_status=0
  probe_k8s_resource namespace "${namespace}" || probe_status=$?
  if [[ "${!namespace_created_var:-false}" == true ]]; then
    case "${probe_status}" in
      0) record_failure "Verification failed: suite-owned namespace ${namespace} still exists" ;;
      1) ;;
      *) record_failure "Verification failed while checking namespace ${namespace}: ${KUBECTL_PROBE_OUTPUT}" ;;
    esac
    return 0
  fi
  case "${probe_status}" in
    0) ;;
    1) record_failure "Verification failed: pre-existing namespace ${namespace} no longer exists"; return 0 ;;
    *) record_failure "Verification failed while checking pre-existing namespace ${namespace}: ${KUBECTL_PROBE_OUTPUT}"; return 0 ;;
  esac

  probe_status=0
  probe_k8s_resource serviceaccount "${service_account}" "${namespace}" || probe_status=$?
  if [[ "${!sa_created_var:-false}" == true ]]; then
    case "${probe_status}" in
      0) record_failure "Verification failed: suite-owned service account ${namespace}/${service_account} still exists" ;;
      1) ;;
      *) record_failure "Verification failed while checking service account ${namespace}/${service_account}: ${KUBECTL_PROBE_OUTPUT}" ;;
    esac
  else
    case "${probe_status}" in
      0) ;;
      1) record_failure "Verification failed: pre-existing service account ${namespace}/${service_account} no longer exists" ;;
      *) record_failure "Verification failed while checking pre-existing service account ${namespace}/${service_account}: ${KUBECTL_PROBE_OUTPUT}" ;;
    esac
  fi

  while IFS='|' read -r kind name backup_var; do
    backup_path="${!backup_var:-}"
    probe_status=0
    probe_k8s_resource "${kind}" "${name}" "${namespace}" || probe_status=$?
    if [[ -n "${backup_path}" ]]; then
      if [[ ! -f "${backup_path}" ]]; then
        record_failure "Verification failed: Kubernetes restore snapshot is missing: ${backup_path}"
        continue
      fi
      case "${probe_status}" in
        0)
          expected_json=$(sanitize_k8s_resource_json < "${backup_path}" | jq -S .)
          actual_json=$(sanitize_k8s_resource_json <<<"${KUBECTL_PROBE_OUTPUT}" | jq -S .)
          [[ "${actual_json}" == "${expected_json}" ]] || \
            record_failure "Verification failed: restored ${kind} ${namespace}/${name} does not match ${backup_path}"
          ;;
        1) record_failure "Verification failed: ${kind} ${namespace}/${name} was not restored from ${backup_path}" ;;
        *) record_failure "Verification failed while checking restored ${kind} ${namespace}/${name}: ${KUBECTL_PROBE_OUTPUT}" ;;
      esac
    else
      case "${probe_status}" in
        0) record_failure "Verification failed: suite-owned ${kind} ${namespace}/${name} still exists" ;;
        1) ;;
        *) record_failure "Verification failed while checking suite-owned ${kind} ${namespace}/${name}: ${KUBECTL_PROBE_OUTPUT}" ;;
      esac
    fi
  done <<EOF
secretproviderclass|${service_account}-secrets|${prefix}_SPC_BACKUP_PATH
deployment|${service_account}|${prefix}_DEPLOYMENT_BACKUP_PATH
service|${service_account}|${prefix}_SERVICE_BACKUP_PATH
ingress|${service_account}|${prefix}_INGRESS_BACKUP_PATH
EOF
}

verify_ecs_restore() {
  [[ -n "${ECS_SERVICE_ARN:-}" ]] || return 0
  local snapshot_path="${ECS_ORIGINAL_PRIMARY_CONTAINER_PATH:-}" expected_primary actual_primary expected_deployment actual_deployment
  [[ -n "${snapshot_path}" && -f "${snapshot_path}" ]] || {
    record_failure "Verification failed: ECS primary-container restore snapshot is unavailable"
    return
  }
  expected_primary=$(jq -S . "${snapshot_path}")
  actual_primary=""
  for i in {1..40}; do
    actual_primary=$(aws_cli ecs describe-express-gateway-service --service-arn "${ECS_SERVICE_ARN}" \
      --query service.activeConfigurations[0].primaryContainer --output json 2>/dev/null | \
      jq -S '{image,containerPort,awsLogsConfiguration,repositoryCredentials,command,environment,secrets} | with_entries(select(.value != null))' || true)
    [[ "${actual_primary}" == "${expected_primary}" ]] && break
    ((i == 40)) || sleep 15
  done
  [[ "${actual_primary}" == "${expected_primary}" ]] || \
    record_failure "Verification failed: ECS primary container does not match ${snapshot_path}"
  if [[ -n "${ECS_ORIGINAL_DEPLOYMENT_CONFIG_B64:-}" ]]; then
    expected_deployment=$(decode_b64 "${ECS_ORIGINAL_DEPLOYMENT_CONFIG_B64}" | jq -S .)
    actual_deployment=$(aws_cli ecs describe-services --cluster aiagent --services aiagent \
      --query 'services[0].deploymentConfiguration' --output json 2>/dev/null | jq -S . || true)
    [[ "${actual_deployment}" == "${expected_deployment}" ]] || \
      record_failure "Verification failed: ECS deployment configuration was not restored"
  fi
}

log "Verifying cleanup results before clearing ownership state"
if [[ "${AGENTCORE_DISTRIBUTION_CREATED:-false}" == true && -n "${AGENTCORE_DISTRIBUTION_ID:-}" ]]; then
  verify_aws_absent "suite-owned CloudFront distribution ${AGENTCORE_DISTRIBUTION_ID}" \
    aws_cli cloudfront get-distribution --id "${AGENTCORE_DISTRIBUTION_ID}"
fi
if [[ "${AGENTCORE_RUNTIME_CREATED:-false}" == true && -n "${AGENTCORE_RUNTIME_ID:-}" ]]; then
  for i in {1..40}; do
    if ! aws_cli bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${AGENTCORE_RUNTIME_ID}" >/dev/null 2>&1; then
      break
    fi
    ((i == 40)) || sleep 15
  done
  verify_aws_absent "suite-owned AgentCore Runtime ${AGENTCORE_RUNTIME_ID}" \
    aws_cli bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${AGENTCORE_RUNTIME_ID}"
fi
if [[ "${AGENTCORE_UI_BUCKET_CREATED:-false}" == true && -n "${AGENTCORE_UI_BUCKET:-}" ]]; then
  verify_aws_absent "suite-owned AgentCore UI bucket ${AGENTCORE_UI_BUCKET}" \
    aws_cli s3api head-bucket --bucket "${AGENTCORE_UI_BUCKET}"
fi
if [[ "${AGENTCORE_OAI_CREATED:-false}" == true && -n "${AGENTCORE_OAI_ID:-}" ]]; then
  verify_aws_absent "suite-owned CloudFront OAI ${AGENTCORE_OAI_ID}" \
    aws_cli cloudfront get-cloud-front-origin-access-identity --id "${AGENTCORE_OAI_ID}"
fi
if [[ -n "${AGENTCORE_LOG_GROUP:-}" ]]; then
  verify_log_group_absent "${AGENTCORE_LOG_GROUP}" "suite-owned AgentCore log group ${AGENTCORE_LOG_GROUP}"
fi

if [[ "${LAMBDA_CREATED:-false}" == true ]]; then
  verify_aws_absent "suite-owned Lambda function aiagent" aws_cli lambda get-function --function-name aiagent
elif [[ "${lambda_function_tracked}" == true ]]; then
  lambda_verify_status=0
  probe_aws_resource_with_retry 5 5 aws_cli lambda get-function-configuration --function-name aiagent || lambda_verify_status=$?
  if [[ "${lambda_verify_status}" == 0 ]]; then
  if [[ "${LAMBDA_URL_CREATED:-false}" == true ]]; then
    verify_aws_absent "suite-created Lambda function URL configuration" aws_cli lambda get-function-url-config --function-name aiagent
  elif [[ -n "${LAMBDA_URL_ORIGINAL_B64:-}" ]]; then
    lambda_url_status=0
    probe_aws_resource_with_retry 5 5 aws_cli lambda get-function-url-config --function-name aiagent || lambda_url_status=$?
    if [[ "${lambda_url_status}" == 0 ]]; then
      expected_url=$(decode_b64 "${LAMBDA_URL_ORIGINAL_B64}" | jq -S '{AuthType,InvokeMode,Cors}')
      actual_url=$(jq -S '{AuthType,InvokeMode,Cors}' <<<"${AWS_PROBE_OUTPUT}")
      [[ "${actual_url}" == "${expected_url}" ]] || record_failure "Verification failed: Lambda function URL configuration was not restored"
    elif [[ "${lambda_url_status}" == 1 ]]; then
      record_failure "Verification failed: original Lambda function URL configuration is missing"
    else
      record_failure "Verification failed: could not read Lambda function URL configuration: ${AWS_PROBE_OUTPUT}"
    fi
  fi
  lambda_policy_status=0
  probe_aws_resource_with_retry 5 5 aws_cli lambda get-policy --function-name aiagent --query Policy --output text || lambda_policy_status=$?
  if [[ "${lambda_policy_status}" == 0 ]]; then
    lambda_policy="${AWS_PROBE_OUTPUT}"
  elif [[ "${lambda_policy_status}" == 1 ]]; then
    lambda_policy='{"Statement":[]}'
  else
    lambda_policy='{"Statement":[]}'
    record_failure "Verification failed: could not read Lambda resource policy: ${AWS_PROBE_OUTPUT}"
  fi
  if [[ "${LAMBDA_PERMISSION_URL_CREATED:-false}" == true ]] && jq -e '.Statement[]? | select(.Sid == "FunctionURLAllowPublicAccess")' >/dev/null <<<"${lambda_policy}"; then
    record_failure "Verification failed: Lambda permission FunctionURLAllowPublicAccess still exists"
  fi
  if [[ "${LAMBDA_PERMISSION_INVOKE_CREATED:-false}" == true ]] && jq -e '.Statement[]? | select(.Sid == "FunctionURLPublicInvoke")' >/dev/null <<<"${lambda_policy}"; then
    record_failure "Verification failed: Lambda permission FunctionURLPublicInvoke still exists"
  fi
  elif [[ "${lambda_verify_status}" == 1 ]]; then
    record_failure "Verification failed: tracked pre-existing Lambda function aiagent no longer exists"
  else
    record_failure "Verification failed: could not read tracked Lambda function aiagent: ${AWS_PROBE_OUTPUT}"
  fi
fi
if [[ "${LAMBDA_PACKAGE_UPLOADED:-false}" == true && -n "${LAMBDA_S3_KEY:-}" ]]; then
  workshop_bucket=$(aws_cli ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
  if [[ "${LAMBDA_PACKAGE_PREEXISTED:-false}" == true ]]; then
    aws_cli s3api head-object --bucket "${workshop_bucket}" --key "${LAMBDA_S3_KEY}" >/dev/null 2>&1 || \
      record_failure "Verification failed: pre-existing Lambda package ${LAMBDA_S3_KEY} was not restored"
    if [[ -n "${LAMBDA_PACKAGE_BACKUP_KEY:-}" ]] && aws_cli s3api head-object --bucket "${workshop_bucket}" --key "${LAMBDA_PACKAGE_BACKUP_KEY}" >/dev/null 2>&1; then
      record_failure "Verification failed: temporary Lambda package backup ${LAMBDA_PACKAGE_BACKUP_KEY} still exists"
    fi
  else
    verify_aws_absent "suite-uploaded Lambda package ${LAMBDA_S3_KEY}" \
      aws_cli s3api head-object --bucket "${workshop_bucket}" --key "${LAMBDA_S3_KEY}"
  fi
fi
if [[ "${LAMBDA_SG_CREATED:-false}" == true && -n "${LAMBDA_SG_ID:-}" ]]; then
  verify_aws_absent "suite-owned Lambda security group ${LAMBDA_SG_ID}" \
    aws_cli ec2 describe-security-groups --group-ids "${LAMBDA_SG_ID}"
fi

verify_ecs_restore
if [[ -n "${EKS_NAMESPACE_CREATED:-}${EKS_SERVICE_ACCOUNT_CREATED:-}${EKS_POD_IDENTITY_ID:-}${EKS_SPC_BACKUP_PATH:-}${EKS_DEPLOYMENT_BACKUP_PATH:-}${EKS_SERVICE_BACKUP_PATH:-}${EKS_INGRESS_BACKUP_PATH:-}" ]]; then
  verify_pod_identity EKS
  verify_k8s_app aiagent EKS aiagent
fi
if [[ -n "${MCP_NAMESPACE_CREATED:-}${MCP_SERVICE_ACCOUNT_CREATED:-}${MCP_POD_IDENTITY_ID:-}${MCP_SPC_BACKUP_PATH:-}${MCP_DEPLOYMENT_BACKUP_PATH:-}${MCP_SERVICE_BACKUP_PATH:-}${MCP_INGRESS_BACKUP_PATH:-}" ]]; then
  verify_pod_identity MCP
  verify_k8s_app mcpserver MCP mcpserver
fi

if [[ -n "${COGNITO_USER_POOL_ID:-}" ]]; then
  if [[ "${COGNITO_POOL_CREATED:-false}" == true ]]; then
    verify_aws_absent "suite-owned Cognito user pool ${COGNITO_USER_POOL_ID}" \
      aws_cli cognito-idp describe-user-pool --user-pool-id "${COGNITO_USER_POOL_ID}"
  else
    IFS=',' read -r -a created_users <<<"${COGNITO_CREATED_USERS:-}"
    for user in "${created_users[@]}"; do
      [[ -n "${user}" ]] && verify_aws_absent "suite-created Cognito user ${user}" \
        aws_cli cognito-idp admin-get-user --user-pool-id "${COGNITO_USER_POOL_ID}" --username "${user}"
    done
    if [[ "${COGNITO_CLIENT_CREATED:-false}" == true && -n "${COGNITO_CLIENT_ID:-}" ]]; then
      verify_aws_absent "suite-created Cognito client ${COGNITO_CLIENT_ID}" \
        aws_cli cognito-idp describe-user-pool-client --user-pool-id "${COGNITO_USER_POOL_ID}" --client-id "${COGNITO_CLIENT_ID}"
    elif [[ -n "${COGNITO_CLIENT_ORIGINAL_CONFIG_B64:-}" ]]; then
      expected_client=$(decode_b64 "${COGNITO_CLIENT_ORIGINAL_CONFIG_B64}")
      current_client=$(aws_cli cognito-idp describe-user-pool-client --user-pool-id "${COGNITO_USER_POOL_ID}" \
        --client-id "${COGNITO_CLIENT_ID}" --query UserPoolClient --output json 2>/dev/null || printf '{}')
      jq -e --argjson expected "${expected_client}" --argjson current "${current_client}" \
        '$expected | to_entries | all(. as $entry | $current[$entry.key] == $entry.value)' >/dev/null || \
        record_failure "Verification failed: Cognito client ${COGNITO_CLIENT_ID} does not match its original configuration"
    fi
  fi
fi

if [[ -n "${BEDROCK_LOGGING_ORIGINAL_B64:-}" ]]; then
  if ! current_logging=$(aws_cli bedrock get-model-invocation-logging-configuration 2>&1); then
    record_failure "Verification failed: could not read Bedrock model invocation logging configuration: ${current_logging}"
  elif [[ "${BEDROCK_LOGGING_ORIGINAL_B64}" == __NONE__ ]]; then
    [[ "$(jq -r '.loggingConfig // empty' <<<"${current_logging}")" == "" ]] || \
      record_failure "Verification failed: Bedrock model invocation logging remains configured"
  else
    expected_logging=$(decode_b64 "${BEDROCK_LOGGING_ORIGINAL_B64}" | jq -S .)
    actual_logging=$(jq -S '.loggingConfig // {}' <<<"${current_logging}")
    [[ "${actual_logging}" == "${expected_logging}" ]] || \
      record_failure "Verification failed: Bedrock model invocation logging was not restored"
  fi
fi
if [[ "${BEDROCK_LOG_GROUP_CREATED:-false}" == true && -n "${BEDROCK_LOG_GROUP:-}" ]]; then
  verify_log_group_absent "${BEDROCK_LOG_GROUP}" "suite-owned Bedrock log group ${BEDROCK_LOG_GROUP}"
fi

if ((${#cleanup_failures[@]} > 0)); then
  warn "Cleanup was incomplete; preserving ownership state in ${STATE_FILE}. Resolve these failures and rerun 99-cleanup.sh --apply:"
  for failure in "${cleanup_failures[@]}"; do
    printf '  - %s\n' "${failure}" >&2
  done
  exit 1
fi

if ! rm -rf "${WORK_DIR}"; then
  record_failure "Could not remove suite work directory ${WORK_DIR}"
fi
if [[ -e "${WORK_DIR}" || ${#cleanup_failures[@]} -gt 0 ]]; then
  [[ -e "${WORK_DIR}" ]] && record_failure "Suite work directory still exists: ${WORK_DIR}"
  warn "Cleanup was incomplete; preserving ownership state in ${STATE_FILE}"
  exit 1
fi
cleanup_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
state_tmp=$(mktemp "${STATE_FILE}.cleanup.XXXXXX")
printf 'export SUITE_ACCOUNT_ID=%q\n' "${ACCOUNT_ID}" > "${state_tmp}"
printf 'export SUITE_AWS_REGION=%q\n' "${AWS_REGION}" >> "${state_tmp}"
printf 'export CLEANUP_LAST_APPLIED=%q\n' "${cleanup_timestamp}" >> "${state_tmp}"
chmod 600 "${state_tmp}"
mv "${state_tmp}" "${STATE_FILE}"
log "Cleanup verified and stale ownership state cleared. Prerequisite infrastructure, repositories, IAM roles, bucket, ECS service, and participant source were preserved."
