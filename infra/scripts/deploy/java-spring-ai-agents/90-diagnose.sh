#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

case "${1:-}" in
  "") ;;
  -h|--help) echo "Usage: 90-diagnose.sh"; exit 0 ;;
  *) die "Usage: 90-diagnose.sh" ;;
esac

print_prerequisites "read-only AWS and optional kubectl access"
init_context_read_only
load_state
set +e

printf '\n== Suite state ==\n'
printf 'State file: %s\nActive target: %s\nEndpoint: %s\n' "${STATE_FILE}" "${ACTIVE_TARGET:-not set}" "${AIAGENT_ENDPOINT:-not set}"
printf 'MCP endpoint: %s\nCognito pool: %s\n' "${MCP_URL:-not set}" "${COGNITO_USER_POOL_ID:-not set}"

printf '\n== Prerequisites ==\n'
aws_cli rds describe-db-clusters --db-cluster-identifier workshop-db-cluster \
  --query 'DBClusters[0].{Status:Status,Engine:Engine,Version:EngineVersion,HttpEndpointEnabled:HttpEndpointEnabled}' --output table
aws_cli secretsmanager describe-secret --secret-id workshop-db-secret \
  --query '{Name:Name,ARN:ARN,LastChangedDate:LastChangedDate}' --output table
aws_cli ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=workshop-db-connection-string \
  --query 'Parameters[0].{Name:Name,Type:Type,LastModifiedDate:LastModifiedDate}' --output table
aws_cli eks describe-cluster --name workshop-eks --query 'cluster.{Status:status,Version:version,Endpoint:endpoint}' --output table
aws_cli ecs describe-services --cluster aiagent --services aiagent \
  --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,Deployments:length(deployments)}' --output table

printf '\n== Suite resources ==\n'
aws_cli cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='aiagent-user-pool'].{Name:Name,Id:Id,Updated:LastModifiedDate}" --output table
aws_cli lambda get-function-configuration --function-name aiagent \
  --query '{State:State,LastUpdateStatus:LastUpdateStatus,Runtime:Runtime,MemorySize:MemorySize,Timeout:Timeout}' --output table
aws_cli bedrock-agentcore-control list-agent-runtimes \
  --query "agentRuntimes[?agentRuntimeName=='aiagent'].{Name:agentRuntimeName,Id:agentRuntimeId,Status:status}" --output table
aws_cli bedrock get-model-invocation-logging-configuration \
  --query 'loggingConfig.{LogGroup:cloudWatchConfig.logGroupName,Bucket:s3Config.bucketName,Text:textDataDeliveryEnabled,Embedding:embeddingDataDeliveryEnabled}' --output table
if command -v kubectl >/dev/null 2>&1; then
  printf '\n== Kubernetes ==\n'
  kubectl get deployment,service,ingress -n mcpserver -o wide
  kubectl get deployment,service,ingress -n aiagent -o wide
fi

printf '\n== Log groups (names only) ==\n'
aws_cli logs describe-log-groups --log-group-name-prefix /aws/bedrock-agentcore/runtimes/ \
  --query 'logGroups[].logGroupName' --output text
aws_cli logs describe-log-groups --log-group-name-prefix /aws/bedrock/model-invocations \
  --query 'logGroups[].logGroupName' --output text
set -e
log "Read-only diagnostics complete. No secrets, tokens, or passwords were requested or printed."
