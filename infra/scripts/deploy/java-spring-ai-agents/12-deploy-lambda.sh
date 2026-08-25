#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "Maven, zip, S3/Lambda/EC2 access, and the shared 02-05 stages"
init_context
load_state
require_cmd mvn
require_cmd zip
require_state MCP_URL COGNITO_ISSUER_URI DB_PARAMETER_NAME DB_SECRET_ID
require_workshop_role aiagent-lambda-role
[[ -f "${AIAGENT_DIR}/pom.xml" ]] || die "AI-agent source not found. Run 01-setup.sh first."

tmp_dir=$(mktemp -d "${WORK_DIR}/lambda.XXXXXX")
trap 'rm -rf "${tmp_dir}"' EXIT
cat > "${AIAGENT_DIR}/run.sh" <<'EOF'
#!/usr/bin/env bash
exec java -jar agent-0.0.1-SNAPSHOT.jar
EOF
chmod +x "${AIAGENT_DIR}/run.sh"
(cd "${AIAGENT_DIR}" && mvn -ntp clean package -DskipTests)
cp "${AIAGENT_DIR}/target/agent-0.0.1-SNAPSHOT.jar" "${AIAGENT_DIR}/run.sh" "${tmp_dir}/"
(cd "${tmp_dir}" && zip -q aiagent-deployment.zip agent-0.0.1-SNAPSHOT.jar run.sh)

WORKSHOP_BUCKET=$(aws_cli ssm get-parameter --name workshop-bucket-name --query 'Parameter.Value' --output text)
S3_KEY="lambda/aiagent-deployment.zip"
if [[ -z "${LAMBDA_PACKAGE_PREEXISTED:-}" ]]; then
  if aws_cli s3api head-object --bucket "${WORKSHOP_BUCKET}" --key "${S3_KEY}" >/dev/null 2>&1; then
    LAMBDA_PACKAGE_BACKUP_KEY="lambda/aiagent-deployment.pre-${SUITE_OWNER}.zip"
    aws_cli s3api copy-object --bucket "${WORKSHOP_BUCKET}" --key "${LAMBDA_PACKAGE_BACKUP_KEY}" \
      --copy-source "${WORKSHOP_BUCKET}/${S3_KEY}" >/dev/null
    state_set LAMBDA_PACKAGE_PREEXISTED true
    state_set LAMBDA_PACKAGE_BACKUP_KEY "${LAMBDA_PACKAGE_BACKUP_KEY}"
  else
    state_set LAMBDA_PACKAGE_PREEXISTED false
  fi
fi
aws_cli s3 cp "${tmp_dir}/aiagent-deployment.zip" "s3://${WORKSHOP_BUCKET}/${S3_KEY}" --only-show-errors
state_set LAMBDA_S3_KEY "${S3_KEY}"
state_set LAMBDA_PACKAGE_UPLOADED true

ROLE_ARN=$(aws_cli iam get-role --role-name aiagent-lambda-role --query 'Role.Arn' --output text)
VPC_ID=$(aws_cli ssm get-parameter --name workshop-vpc-id --query 'Parameter.Value' --output text 2>/dev/null || true)
if is_none "${VPC_ID}"; then
  VPC_ID=$(aws_cli ec2 describe-vpcs --filters Name=tag:Name,Values=workshop-vpc --query 'Vpcs[0].VpcId' --output text)
fi
SUBNET_JSON=$(aws_cli ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:aws-cdk:subnet-type,Values=Private" \
  --query 'Subnets[*].SubnetId' --output json)
[[ "$(jq length <<<"${SUBNET_JSON}")" -gt 0 ]] || die "No private subnets found in ${VPC_ID}"
SG_ID=$(aws_cli ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=aiagent-lambda-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)
if is_none "${SG_ID}"; then
  SG_ID=$(aws_cli ec2 create-security-group --group-name aiagent-lambda-sg \
    --description "AI Agent Lambda security group managed by ${SUITE_OWNER}" --vpc-id "${VPC_ID}" --query GroupId --output text)
  aws_cli ec2 create-tags --resources "${SG_ID}" --tags "Key=suite,Value=${SUITE_OWNER}" >/dev/null
  state_set LAMBDA_SG_CREATED true
else
  [[ -n "${LAMBDA_SG_CREATED:-}" ]] || state_set LAMBDA_SG_CREATED false
fi
state_set LAMBDA_SG_ID "${SG_ID}"

DB_URL=$(aws_cli ssm get-parameter --name "${DB_PARAMETER_NAME}" --query Parameter.Value --output text)
DB_JSON=$(aws_cli secretsmanager get-secret-value --secret-id "${DB_SECRET_ID}" --query SecretString --output text)
DB_USER=$(jq -r .username <<<"${DB_JSON}")
DB_PASS=$(jq -r .password <<<"${DB_JSON}")
ENV_FILE="${tmp_dir}/environment.json"
jq -n --arg db_url "${DB_URL}" --arg db_user "${DB_USER}" --arg db_pass "${DB_PASS}" \
  --arg mcp "${MCP_URL}" --arg issuer "${COGNITO_ISSUER_URI}" \
  '{Variables:{PORT:"8080",AWS_LWA_ENABLE_COMPRESSION:"false",SPRING_PROFILES_ACTIVE:"lambda",AWS_LAMBDA_EXEC_WRAPPER:"/opt/bootstrap",AWS_LWA_INVOKE_MODE:"response_stream",SPRING_DATASOURCE_URL:$db_url,SPRING_DATASOURCE_USERNAME:$db_user,SPRING_DATASOURCE_PASSWORD:$db_pass,SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL:$mcp,SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI:$issuer}}' > "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
unset DB_JSON DB_USER DB_PASS
VPC_CONFIG=$(jq -nc --argjson subnets "${SUBNET_JSON}" --arg sg "${SG_ID}" '{SubnetIds:$subnets,SecurityGroupIds:[$sg]}')
LAYER_ARN="arn:aws:lambda:${AWS_REGION}:753240598075:layer:LambdaAdapterLayerX86:25"

if aws_cli lambda get-function --function-name aiagent >/dev/null 2>&1; then
  if [[ "${LAMBDA_CREATED:-}" != true && -z "${LAMBDA_BACKUP_VERSION:-}" ]]; then
    state_set LAMBDA_CREATED false
    BACKUP_VERSION=$(aws_cli lambda publish-version --function-name aiagent \
      --description "Pre-${SUITE_OWNER} backup" --query Version --output text)
    state_set LAMBDA_BACKUP_VERSION "${BACKUP_VERSION}"
  fi
  aws_cli lambda update-function-code --function-name aiagent --s3-bucket "${WORKSHOP_BUCKET}" --s3-key "${S3_KEY}" >/dev/null
  aws_cli lambda wait function-updated-v2 --function-name aiagent
  aws_cli lambda update-function-configuration --function-name aiagent --runtime java25 --role "${ROLE_ARN}" \
    --handler run.sh --timeout 60 --memory-size 2048 --layers "${LAYER_ARN}" \
    --environment "file://${ENV_FILE}" --vpc-config "${VPC_CONFIG}" >/dev/null
  aws_cli lambda wait function-updated-v2 --function-name aiagent
else
  aws_cli lambda create-function --function-name aiagent --runtime java25 --role "${ROLE_ARN}" --handler run.sh \
    --code "S3Bucket=${WORKSHOP_BUCKET},S3Key=${S3_KEY}" --timeout 60 --memory-size 2048 \
    --layers "${LAYER_ARN}" --environment "file://${ENV_FILE}" --vpc-config "${VPC_CONFIG}" \
    --tags "suite=${SUITE_OWNER}" >/dev/null
  state_set LAMBDA_CREATED true
  aws_cli lambda wait function-active-v2 --function-name aiagent
fi

CORS='AllowOrigins=*,AllowMethods=*,AllowHeaders=date,keep-alive,x-custom-header,content-type,ExposeHeaders=date,keep-alive,MaxAge=86400'
if URL_CONFIG=$(aws_cli lambda get-function-url-config --function-name aiagent 2>/dev/null); then
  if [[ -z "${LAMBDA_URL_ORIGINAL_B64:-}" ]]; then
    state_set LAMBDA_URL_CREATED false
    state_set LAMBDA_URL_ORIGINAL_B64 "$(encode_b64 "$(jq -c '{AuthType,InvokeMode,Cors}' <<<"${URL_CONFIG}")")"
  fi
  aws_cli lambda update-function-url-config --function-name aiagent --auth-type NONE --invoke-mode RESPONSE_STREAM --cors "${CORS}" >/dev/null
else
  aws_cli lambda create-function-url-config --function-name aiagent --auth-type NONE --invoke-mode RESPONSE_STREAM --cors "${CORS}" >/dev/null
  state_set LAMBDA_URL_CREATED true
fi

POLICY=$(aws_cli lambda get-policy --function-name aiagent --query Policy --output text 2>/dev/null || printf '{"Statement":[]}')
if ! jq -e '.Statement[]? | select(.Sid == "FunctionURLAllowPublicAccess")' >/dev/null <<<"${POLICY}"; then
  aws_cli lambda add-permission --function-name aiagent --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl --principal '*' --function-url-auth-type NONE >/dev/null
  state_set LAMBDA_PERMISSION_URL_CREATED true
fi
if ! jq -e '.Statement[]? | select(.Sid == "FunctionURLPublicInvoke")' >/dev/null <<<"${POLICY}"; then
  aws_cli lambda add-permission --function-name aiagent --statement-id FunctionURLPublicInvoke \
    --action lambda:InvokeFunction --principal '*' --invoked-via-function-url >/dev/null
  state_set LAMBDA_PERMISSION_INVOKE_CREATED true
fi

AIAGENT_ENDPOINT=$(aws_cli lambda get-function-url-config --function-name aiagent --query FunctionUrl --output text)
wait_for_http_status "Lambda AI-agent" "${AIAGENT_ENDPOINT}" '^(200)$' 30 10
state_set ACTIVE_TARGET lambda
state_set AIAGENT_ENDPOINT "${AIAGENT_ENDPOINT%/}"
log "AI agent created or updated on Lambda using s3://${WORKSHOP_BUCKET}/${S3_KEY}: ${AIAGENT_ENDPOINT}"
