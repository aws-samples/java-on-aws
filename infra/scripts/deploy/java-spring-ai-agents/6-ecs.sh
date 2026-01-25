#!/bin/bash

# Deploy AI Agent to Amazon ECS Express Mode
# Based on: java-spring-ai-agents/content/deploy/ecs/index.en.md

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/aiagent
APP_NAME="aiagent"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

log_info "Deploying AI Agent to Amazon ECS..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"
log_info "ECR URI: ${ECR_URI}"

# Verify application exists
if [[ ! -d "${APP_DIR}" ]]; then
    log_error "AI Agent application not found at ${APP_DIR}. Run 3-app.sh first."
    exit 1
fi

# ============================================================================
# Add Jib plugin and build container image
# ============================================================================
log_info "Adding Jib plugin to pom.xml..."
grep -q 'jib-maven-plugin' ~/environment/aiagent/pom.xml || \
sed -i '/<\/plugins>/i\
			<plugin>\
				<groupId>com.google.cloud.tools</groupId>\
				<artifactId>jib-maven-plugin</artifactId>\
				<version>3.5.1</version>\
				<configuration>\
					<from>\
						<image>public.ecr.aws/docker/library/amazoncorretto:25-alpine</image>\
					</from>\
					<container>\
						<user>1000</user>\
					</container>\
				</configuration>\
			</plugin>' ~/environment/aiagent/pom.xml
log_success "Jib plugin added"

log_info "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
log_success "ECR login successful"

log_info "Building and pushing container image with Jib..."
cd ~/environment/aiagent
mvn compile jib:build \
  -Dimage=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent:latest \
  -DskipTests
log_success "Container image pushed"

# ============================================================================
# Configure ECS deployment
# ============================================================================
log_info "Configuring faster deployment for workshop..."
aws ecs update-service \
  --cluster ${APP_NAME} \
  --service ${APP_NAME} \
  --deployment-configuration '{
    "maximumPercent": 200,
    "minimumHealthyPercent": 0,
    "bakeTimeInMinutes": 0,
    "canaryConfiguration": {"canaryPercent": 100, "canaryBakeTimeInMinutes": 0}
  }' \
  --no-cli-pager > /dev/null
log_success "Deployment configuration updated"

# Get MCP URL and Cognito Issuer URI
log_info "Getting MCP Server URL and Cognito configuration..."
MCP_URL=http://$(kubectl get ingress mcpserver -n mcpserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "MCP URL: ${MCP_URL}"

USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)
COGNITO_ISSUER_URI="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
echo "Cognito Issuer URI: ${COGNITO_ISSUER_URI}"

# Update task definition
log_info "Updating ECS task definition..."
AI_SERVICE_ARN=$(aws ecs describe-services --cluster aiagent --services aiagent \
  --query 'services[0].serviceArn' --output text --no-cli-pager)
IMAGE=$(aws ecs describe-express-gateway-service --service-arn ${AI_SERVICE_ARN} \
  --query 'service.activeConfigurations[0].primaryContainer.image' --output text --no-cli-pager)

aws ecs update-express-gateway-service \
  --service-arn ${AI_SERVICE_ARN} \
  --primary-container \
  "{\"image\":\"${IMAGE}\",\"environment\":[{\"name\":\"SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL\",\"value\":\"${MCP_URL}\"},{\"name\":\"SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI\",\"value\":\"${COGNITO_ISSUER_URI}\"}]}" \
  --no-cli-pager > /dev/null
log_success "Task definition updated"

# ============================================================================
# Wait for deployment
# ============================================================================
log_info "Waiting for deployment to complete (this may take 2-5 minutes)..."
while [[ $(aws ecs describe-services --cluster ${APP_NAME} --services ${APP_NAME} \
  --query 'services[0].deployments | length(@)' --output text --no-cli-pager) -gt 1 ]]; do
  echo "Waiting for deployment to complete..." && sleep 15
done
log_success "Deployment complete"

# ============================================================================
# Get Service URL and test
# ============================================================================
log_info "Getting Service URL..."
SERVICE_ARN=$(aws ecs describe-services --cluster ${APP_NAME} --services ${APP_NAME} \
  --query 'services[0].serviceArn' --output text --no-cli-pager)
SVC_URL=https://$(aws ecs describe-express-gateway-service --service-arn ${SERVICE_ARN} \
  --query 'service.activeConfigurations[0].ingressPaths[0].endpoint' --output text --no-cli-pager)

log_info "Waiting for service to be ready..."
while ! curl -s --max-time 5 "${SVC_URL}/actuator/health" | grep -q '"status":"UP"'; do
  echo "Waiting for service..." && sleep 15
done

log_success "ECS deployment completed"
echo "✅ Success: AI Agent deployed to ECS"
echo "URL: ${SVC_URL}"
echo "Username: alice"
echo "Password: ${IDE_PASSWORD}"
