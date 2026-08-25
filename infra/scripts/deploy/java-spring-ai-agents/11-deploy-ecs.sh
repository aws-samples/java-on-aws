#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "docker, Maven, and the precreated aiagent ECS Express service"
init_context
load_state
require_state MCP_URL COGNITO_ISSUER_URI
[[ -f "${AIAGENT_DIR}/pom.xml" ]] || die "AI-agent source not found. Run 01-setup.sh first."

build_and_push_jib "${AIAGENT_DIR}" aiagent alternative
IMAGE_DIGEST=$(aws_cli ecr describe-images --repository-name aiagent --image-ids imageTag=alternative \
  --query 'imageDetails[0].imageDigest' --output text)
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent@${IMAGE_DIGEST}"

SERVICE=$(aws_cli ecs describe-services --cluster aiagent --services aiagent --query 'services[0]')
SERVICE_ARN=$(jq -r '.serviceArn // empty' <<<"${SERVICE}")
[[ -n "${SERVICE_ARN}" ]] || die "Precreated ECS service aiagent was not found"
EXPRESS=$(aws_cli ecs describe-express-gateway-service --service-arn "${SERVICE_ARN}" --query service)
CURRENT_CONTAINER=$(jq -c '.activeConfigurations[0].primaryContainer' <<<"${EXPRESS}")
CURRENT_ENV=$(jq -c '.environment // []' <<<"${CURRENT_CONTAINER}")

if [[ -z "${ECS_ORIGINAL_DEPLOYMENT_CONFIG_B64:-}" ]]; then
  state_set ECS_ORIGINAL_DEPLOYMENT_CONFIG_B64 "$(encode_b64 "$(jq -c '.deploymentConfiguration' <<<"${SERVICE}")")"
fi
if [[ -z "${ECS_ORIGINAL_PRIMARY_CONTAINER_PATH:-}" ]]; then
  backup_dir="${WORK_DIR}/ecs-backups"
  mkdir -p "${backup_dir}"
  chmod 700 "${backup_dir}"
  backup_file="${backup_dir}/original-primary-container.json"
  if [[ -n "${ECS_ORIGINAL_PRIMARY_CONTAINER_B64:-}" ]]; then
    decode_b64 "${ECS_ORIGINAL_PRIMARY_CONTAINER_B64}" > "${backup_file}"
  else
    jq -c '{image,containerPort,awsLogsConfiguration,repositoryCredentials,command,environment,secrets} | with_entries(select(.value != null))' \
      <<<"${CURRENT_CONTAINER}" > "${backup_file}"
  fi
  chmod 600 "${backup_file}"
  state_set ECS_ORIGINAL_PRIMARY_CONTAINER_PATH "${backup_file}"
  state_unset ECS_ORIGINAL_PRIMARY_CONTAINER_B64
elif [[ ! -f "${ECS_ORIGINAL_PRIMARY_CONTAINER_PATH}" ]]; then
  die "ECS restore snapshot is missing: ${ECS_ORIGINAL_PRIMARY_CONTAINER_PATH}"
fi

aws_cli ecs update-service --cluster aiagent --service aiagent --deployment-configuration \
  '{"maximumPercent":200,"minimumHealthyPercent":0,"bakeTimeInMinutes":0,"canaryConfiguration":{"canaryPercent":100,"canaryBakeTimeInMinutes":0}}' >/dev/null
DESIRED_ENV=$(jq -c --arg mcp "${MCP_URL}" --arg issuer "${COGNITO_ISSUER_URI}" '
  map(select(.name != "SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL" and .name != "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI"))
  + [{name:"SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL",value:$mcp},{name:"SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI",value:$issuer}]' <<<"${CURRENT_ENV}")
PRIMARY=$(jq -c --arg image "${IMAGE_URI}" --argjson env "${DESIRED_ENV}" '{image,containerPort,awsLogsConfiguration,repositoryCredentials,command,secrets} | with_entries(select(.value != null)) | .image=$image | .environment=$env' <<<"${CURRENT_CONTAINER}")
aws_cli ecs update-express-gateway-service --service-arn "${SERVICE_ARN}" --primary-container "${PRIMARY}" >/dev/null

stable=false
for i in {1..40}; do
  SERVICE_STATUS=$(aws_cli ecs describe-services --cluster aiagent --services aiagent --query 'services[0]')
  deployments=$(jq '.deployments | length' <<<"${SERVICE_STATUS}")
  running=$(jq -r '.runningCount' <<<"${SERVICE_STATUS}")
  desired=$(jq -r '.desiredCount' <<<"${SERVICE_STATUS}")
  active_image=$(aws_cli ecs describe-express-gateway-service --service-arn "${SERVICE_ARN}" \
    --query 'service.activeConfigurations[0].primaryContainer.image' --output text)
  if [[ "${deployments}" == "1" && "${running}" == "${desired}" && "${active_image}" == "${IMAGE_URI}" ]]; then stable=true; break; fi
  log "Waiting for ECS deployment (${i}/40): deployments=${deployments}, running=${running}/${desired}"
  ((i == 40)) || sleep 15
done
[[ "${stable}" == true ]] || die "ECS deployment did not stabilize on image ${IMAGE_URI}"
ENDPOINT_HOST=$(aws_cli ecs describe-express-gateway-service --service-arn "${SERVICE_ARN}" \
  --query 'service.activeConfigurations[0].ingressPaths[0].endpoint' --output text)
[[ -n "${ENDPOINT_HOST}" && "${ENDPOINT_HOST}" != "None" ]] || die "ECS Express endpoint is unavailable"
AIAGENT_ENDPOINT="https://${ENDPOINT_HOST}"
wait_for_http_status "ECS AI-agent health" "${AIAGENT_ENDPOINT}/actuator/health" '^(200)$' 30 10
state_set ECS_SERVICE_ARN "${SERVICE_ARN}"
state_set ECS_IMAGE_URI "${IMAGE_URI}"
state_set ACTIVE_TARGET ecs
state_set AIAGENT_ENDPOINT "${AIAGENT_ENDPOINT}"
log "AI agent updated on the precreated ECS service: ${AIAGENT_ENDPOINT}. The service is never deleted by this suite."
