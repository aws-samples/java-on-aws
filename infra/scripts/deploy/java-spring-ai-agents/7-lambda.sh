#!/bin/bash

# Deploy AI Agent to AWS Lambda with Lambda Web Adapter
# Based on: java-spring-ai-agents/content/deploy/lambda/index.en.md

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/aiagent
APP_NAME="aiagent"

log_info "Deploying AI Agent to AWS Lambda..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"

# Verify application exists
if [[ ! -d "${APP_DIR}" ]]; then
    log_error "AI Agent application not found at ${APP_DIR}. Run 3-app.sh first."
    exit 1
fi

# ============================================================================
# Create runtime script and build
# ============================================================================
log_info "Creating Lambda runtime script..."
cat > ~/environment/aiagent/run.sh << 'EOF'
#!/bin/bash
java -jar agent-0.0.1-SNAPSHOT.jar
EOF
chmod +x ~/environment/aiagent/run.sh
log_success "Runtime script created"

log_info "Building application..."
cd ~/environment/aiagent
mvn clean package -DskipTests
log_success "Application built"

log_info "Creating deployment package..."
cd target
cp ../run.sh .
zip -r aiagent-deployment.zip agent-0.0.1-SNAPSHOT.jar run.sh
log_success "Deployment package created"

# ============================================================================
# Get configuration
# ============================================================================
log_info "Getting MCP Server URL and Cognito configuration..."
MCP_URL=http://$(kubectl get ingress mcpserver -n mcpserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "MCP URL: ${MCP_URL}"

ROLE_ARN=$(aws iam get-role --role-name aiagent-lambda-role \
  --query 'Role.Arn' --output text --no-cli-pager)

USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)
COGNITO_ISSUER_URI="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
echo "Cognito Issuer URI: ${COGNITO_ISSUER_URI}"

log_info "Getting database credentials..."
export SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name workshop-db-connection-string --no-cli-pager \
  | jq --raw-output '.Parameter.Value')
export SPRING_DATASOURCE_USERNAME=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager \
  | jq --raw-output '.SecretString' | jq -r .username)
export SPRING_DATASOURCE_PASSWORD=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager \
  | jq --raw-output '.SecretString' | jq -r .password)

log_info "Creating environment variables file..."
cat > env-vars.json << EOF
{
  "Variables": {
    "PORT": "8080",
    "AWS_LWA_ENABLE_COMPRESSION": "false",
    "SPRING_PROFILES_ACTIVE": "lambda",
    "AWS_LAMBDA_EXEC_WRAPPER": "/opt/bootstrap",
    "AWS_LWA_INVOKE_MODE": "response_stream",
    "SPRING_DATASOURCE_URL": "${SPRING_DATASOURCE_URL}",
    "SPRING_DATASOURCE_USERNAME": "${SPRING_DATASOURCE_USERNAME}",
    "SPRING_DATASOURCE_PASSWORD": "${SPRING_DATASOURCE_PASSWORD}",
    "SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL": "${MCP_URL}",
    "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI": "${COGNITO_ISSUER_URI}"
  }
}
EOF
log_success "Environment variables configured"

# ============================================================================
# Get VPC configuration
# ============================================================================
log_info "Getting VPC configuration..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=workshop-vpc" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager)
echo "VPC ID: ${VPC_ID}"

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*PrivateSubnet*" \
  --query 'Subnets[*].SubnetId' \
  --output text --no-cli-pager | tr '\t' ',')
echo "Private Subnets: ${SUBNET_IDS}"

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=aiagent-lambda-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text --no-cli-pager)

if [ "${SECURITY_GROUP_ID}" = "None" ] || [ -z "${SECURITY_GROUP_ID}" ]; then
  log_info "Creating security group..."
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name aiagent-lambda-sg \
    --description "Security group for AI Agent Lambda function" \
    --vpc-id ${VPC_ID} \
    --query 'GroupId' \
    --output text --no-cli-pager)

  aws ec2 authorize-security-group-egress \
    --group-id ${SECURITY_GROUP_ID} \
    --protocol all \
    --cidr 0.0.0.0/0 \
    --no-cli-pager > /dev/null 2>&1 || true
fi
echo "Security Group: ${SECURITY_GROUP_ID}"
log_success "VPC configuration ready"

# ============================================================================
# Create Lambda function
# ============================================================================
log_info "Creating Lambda function..."
aws lambda create-function \
  --function-name aiagent \
  --runtime java25 \
  --role "${ROLE_ARN}" \
  --handler run.sh \
  --zip-file fileb://aiagent-deployment.zip \
  --timeout 60 \
  --memory-size 2048 \
  --layers arn:aws:lambda:${AWS_REGION}:753240598075:layer:LambdaAdapterLayerX86:25 \
  --environment file://env-vars.json \
  --vpc-config SubnetIds="${SUBNET_IDS}",SecurityGroupIds="${SECURITY_GROUP_ID}" \
  --no-cli-pager > /dev/null
log_success "Lambda function created"

# ============================================================================
# Create Function URL with streaming
# ============================================================================
log_info "Creating Function URL with streaming support..."
aws lambda create-function-url-config \
  --function-name aiagent \
  --auth-type NONE \
  --invoke-mode RESPONSE_STREAM \
  --cors AllowOrigins="*",AllowMethods="*",AllowHeaders="date,keep-alive,x-custom-header,content-type",ExposeHeaders="date,keep-alive",MaxAge=86400 \
  --no-cli-pager > /dev/null
log_success "Function URL created"

# Add permissions
log_info "Adding resource-based policies..."
aws lambda add-permission \
  --function-name aiagent \
  --statement-id FunctionURLAllowPublicAccess \
  --action lambda:InvokeFunctionUrl \
  --principal "*" \
  --function-url-auth-type NONE \
  --no-cli-pager > /dev/null

aws lambda add-permission \
  --function-name aiagent \
  --statement-id FunctionURLPublicInvoke \
  --action lambda:InvokeFunction \
  --principal "*" \
  --invoked-via-function-url \
  --no-cli-pager > /dev/null
log_success "Permissions added"

# ============================================================================
# Wait and test
# ============================================================================
log_info "Getting Function URL..."
FUNCTION_URL=$(aws lambda get-function-url-config \
  --function-name aiagent \
  --query 'FunctionUrl' \
  --output text \
  --no-cli-pager)
echo "Function URL: ${FUNCTION_URL}"

log_info "Waiting for Lambda to become available (this may take 1-3 minutes)..."
while true; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${FUNCTION_URL}" || echo "000")
  echo "Lambda HTTP status: ${HTTP_STATUS}"
  if [ "${HTTP_STATUS}" = "200" ]; then break; fi
  sleep 15
done

log_success "AI Agent URL: ${FUNCTION_URL}"

log_success "Lambda deployment completed"
echo "✅ Success: AI Agent deployed to Lambda (URL: ${FUNCTION_URL})"
