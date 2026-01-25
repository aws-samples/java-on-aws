#!/bin/bash

# Deploy AI Agent to Amazon Bedrock AgentCore
# Based on: java-spring-ai-agents/content/deploy/agentcore/index.en.md

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/aiagent
APP_NAME="aiagent"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

log_info "Deploying AI Agent to Amazon Bedrock AgentCore..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"
log_info "ECR URI: ${ECR_URI}"

# Verify application exists
if [[ ! -d "${APP_DIR}" ]]; then
    log_error "AI Agent application not found at ${APP_DIR}. Run 3-app.sh first."
    exit 1
fi

# ============================================================================
# Add AgentCore dependencies
# ============================================================================
log_info "Adding AgentCore dependencies to pom.xml..."
grep -q 'spring-ai-bedrock-agentcore-starter' ~/environment/aiagent/pom.xml || \
sed -i '0,/<dependencies>/{/<dependencies>/a\
        <!-- AgentCore dependencies -->\
        <dependency>\
            <groupId>org.springaicommunity</groupId>\
            <artifactId>spring-ai-bedrock-agentcore-starter</artifactId>\
            <version>1.0.0-RC3</version>\
        </dependency>
}' ~/environment/aiagent/pom.xml
log_success "AgentCore dependencies added"

# ============================================================================
# Create InvocationService
# ============================================================================
log_info "Creating InvocationService.java..."
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/InvocationService.java
package com.example.agent;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Base64;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

@Service
@ConditionalOnProperty(name = "app.controller.enabled", havingValue = "false", matchIfMissing = false)
public class InvocationService {
    private final ChatService chatService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public InvocationService(ChatService chatService) {
        this.chatService = chatService;
    }

    @AgentCoreInvocation
    public Flux<String> handleInvocation(InvocationRequest request, AgentCoreContext context) throws Exception {
        String jwt = context.getHeader(AgentCoreHeaders.AUTHORIZATION).replace("Bearer ", "");
        String payload = new String(Base64.getUrlDecoder().decode(jwt.split("\\.")[1]));
        JsonNode claims = objectMapper.readTree(payload);
        String visitorId = claims.get("sub").asText().replace("-", "").substring(0, 25);
        String authTime = claims.get("auth_time").asText();
        String sessionId = visitorId + ":" + authTime;
        return chatService.chat(request.prompt(), sessionId);
    }
}
EOF
log_success "InvocationService.java created"

# ============================================================================
# Create Dockerfile
# ============================================================================
log_info "Creating Dockerfile..."
cat <<'EOF' > ~/environment/aiagent/Dockerfile
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-25-al2023 AS builder

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN rm -rf src/main/resources/static
RUN mvn clean package -DskipTests -ntp && mv target/*.jar app.jar

FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023

RUN yum install -y shadow-utils

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

COPY --from=builder app.jar app.jar

USER 1000:1000
EXPOSE 8080
ENV APP_CONTROLLER_ENABLED=false

ENTRYPOINT ["java", "-jar", "/app.jar"]
EOF
log_success "Dockerfile created"

# ============================================================================
# Build and push container image
# ============================================================================
log_info "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
  docker login --username AWS --password-stdin ${ECR_URI}
log_success "ECR login successful"

log_info "Setting up Docker buildx for ARM64..."
docker run --privileged --rm tonistiigi/binfmt --install arm64 > /dev/null 2>&1
docker buildx create --name arm64builder --use > /dev/null 2>&1 || docker buildx use arm64builder > /dev/null 2>&1
docker buildx inspect --bootstrap > /dev/null 2>&1
log_success "Docker buildx configured"

log_info "Building and pushing Docker image (ARM64)..."
cd ~/environment/aiagent
docker buildx build --platform linux/arm64 -t ${ECR_URI}:agentcore --push .
log_success "Container image pushed"

# ============================================================================
# Get VPC and network configuration
# ============================================================================
log_info "Getting VPC configuration..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=workshop-vpc" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=tag:aws-cdk:subnet-type,Values=Private" \
            "Name=availability-zone-id,Values=use1-az1,use1-az2,use1-az4" \
  --query 'Subnets[*].SubnetId' --output json --no-cli-pager)

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=workshop-db-sg" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)

echo "VPC: ${VPC_ID}"
echo "Subnets: ${SUBNET_IDS}"
echo "Security Group: ${SG_ID}"
log_success "VPC configuration ready"

# ============================================================================
# Get database and MCP configuration
# ============================================================================
log_info "Getting database credentials and MCP Server URL..."
DB_URL=$(aws ssm get-parameter --name workshop-db-connection-string --no-cli-pager \
  | jq -r '.Parameter.Value')
DB_USER=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager \
  | jq -r '.SecretString' | jq -r .username)
DB_PASS=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager \
  | jq -r '.SecretString' | jq -r .password)

MCP_URL=http://$(kubectl get ingress mcpserver -n mcpserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "DB URL: ${DB_URL}"
echo "MCP URL: ${MCP_URL}"
log_success "Configuration ready"

# ============================================================================
# Create AgentCore Runtime
# ============================================================================
log_info "Creating AgentCore Runtime..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)
CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "${USER_POOL_ID}" --no-cli-pager \
  --query "UserPoolClients[?ClientName=='aiagent-client'].ClientId | [0]" --output text)
COGNITO_DISCOVERY="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}/.well-known/openid-configuration"

ENV_VARS=$(jq -n \
  --arg db_url "${DB_URL}" \
  --arg db_user "${DB_USER}" \
  --arg db_pass "${DB_PASS}" \
  --arg mcp_url "${MCP_URL}" \
  '{SPRING_DATASOURCE_URL: $db_url, SPRING_DATASOURCE_USERNAME: $db_user, SPRING_DATASOURCE_PASSWORD: $db_pass, SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL: $mcp_url}')

RUNTIME_RESPONSE=$(aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name aiagent \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-agentcore-runtime-role" \
  --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:agentcore\"}}" \
  --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":${SUBNET_IDS},\"securityGroups\":[\"${SG_ID}\"]}}" \
  --authorizer-configuration "{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${COGNITO_DISCOVERY}\",\"allowedClients\":[\"${CLIENT_ID}\"]}}" \
  --request-header-configuration '{"requestHeaderAllowlist":["Authorization"]}' \
  --environment-variables "${ENV_VARS}" \
  --region ${AWS_REGION} \
  --no-cli-pager)

RUNTIME_ID=$(echo "${RUNTIME_RESPONSE}" | jq -r '.agentRuntimeId')
echo "Runtime ID: ${RUNTIME_ID}"
log_success "AgentCore Runtime created"

# ============================================================================
# Wait for runtime to be ready
# ============================================================================
log_info "Waiting for runtime to be ready (this may take 3-5 minutes)..."
while true; do
  STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${RUNTIME_ID}" \
    --region ${AWS_REGION} \
    --query 'status' --output text --no-cli-pager)
  echo "Status: ${STATUS}"
  if [ "${STATUS}" = "READY" ]; then break; fi
  if [ "${STATUS}" = "FAILED" ]; then
    log_error "Runtime failed"
    exit 1
  fi
  sleep 15
done
log_success "Runtime ready"

# ============================================================================
# Test the deployment
# ============================================================================
log_info "Getting AgentCore endpoint..."
RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"
RUNTIME_ARN_ENCODED=$(echo -n "${RUNTIME_ARN}" | jq -sRr @uri)
API_ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/${RUNTIME_ARN_ENCODED}/invocations?qualifier=DEFAULT"

log_info "Getting Cognito token..."
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id ${CLIENT_ID} \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=alice,PASSWORD=${IDE_PASSWORD} \
  --region ${AWS_REGION} \
  --no-cli-pager \
  --query 'AuthenticationResult.AccessToken' --output text)

log_info "Testing AgentCore endpoint..."
curl -N -X POST "${API_ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"prompt": "Hello"}' | sed 's/^data://g' | tr -d '\n'; echo
log_success "AgentCore endpoint test completed"

# ============================================================================
# Deploy UI to S3 and CloudFront
# ============================================================================
log_info "Creating S3 bucket for UI..."
UI_BUCKET="aiagent-ui-${ACCOUNT_ID}-$(date +%s)"

if [ "${AWS_REGION}" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "${UI_BUCKET}" --no-cli-pager > /dev/null
else
  aws s3api create-bucket --bucket "${UI_BUCKET}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" --no-cli-pager > /dev/null
fi
log_success "S3 bucket created: ${UI_BUCKET}"

log_info "Creating CloudFront Origin Access Identity..."
OAI_RESPONSE=$(aws cloudfront create-cloud-front-origin-access-identity \
  --cloud-front-origin-access-identity-config \
    "{\"CallerReference\":\"aiagent-$(date +%s)\",\"Comment\":\"OAI for aiagent UI\"}" \
  --no-cli-pager)
OAI_ID=$(echo "${OAI_RESPONSE}" | jq -r '.CloudFrontOriginAccessIdentity.Id')
OAI_CANONICAL=$(aws cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" \
  --no-cli-pager --query 'CloudFrontOriginAccessIdentity.S3CanonicalUserId' --output text)
log_success "OAI created: ${OAI_ID}"

log_info "Updating S3 bucket policy..."
aws s3api put-bucket-policy --bucket "${UI_BUCKET}" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Effect\": \"Allow\",
    \"Principal\": {\"CanonicalUser\": \"${OAI_CANONICAL}\"},
    \"Action\": \"s3:GetObject\",
    \"Resource\": \"arn:aws:s3:::${UI_BUCKET}/*\"
  }]
}" --no-cli-pager
log_success "Bucket policy updated"

log_info "Creating CloudFront distribution..."
CF_RESPONSE=$(aws cloudfront create-distribution \
  --distribution-config "{
    \"CallerReference\": \"aiagent-$(date +%s)\",
    \"Comment\": \"aiagent UI\",
    \"Enabled\": true,
    \"DefaultRootObject\": \"index.html\",
    \"Origins\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"Id\": \"S3-${UI_BUCKET}\",
        \"DomainName\": \"${UI_BUCKET}.s3.${AWS_REGION}.amazonaws.com\",
        \"S3OriginConfig\": {
          \"OriginAccessIdentity\": \"origin-access-identity/cloudfront/${OAI_ID}\"
        }
      }]
    },
    \"DefaultCacheBehavior\": {
      \"TargetOriginId\": \"S3-${UI_BUCKET}\",
      \"ViewerProtocolPolicy\": \"redirect-to-https\",
      \"AllowedMethods\": {
        \"Quantity\": 2,
        \"Items\": [\"GET\", \"HEAD\"],
        \"CachedMethods\": {\"Quantity\": 2, \"Items\": [\"GET\", \"HEAD\"]}
      },
      \"ForwardedValues\": {\"QueryString\": false, \"Cookies\": {\"Forward\": \"none\"}},
      \"MinTTL\": 0,
      \"DefaultTTL\": 86400,
      \"MaxTTL\": 31536000,
      \"Compress\": true
    },
    \"CustomErrorResponses\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"ErrorCode\": 403,
        \"ResponsePagePath\": \"/index.html\",
        \"ResponseCode\": \"200\",
        \"ErrorCachingMinTTL\": 300
      }]
    },
    \"PriceClass\": \"PriceClass_100\"
  }" \
  --no-cli-pager)

CF_DIST_ID=$(echo "${CF_RESPONSE}" | jq -r '.Distribution.Id')
CF_DOMAIN=$(echo "${CF_RESPONSE}" | jq -r '.Distribution.DomainName')
log_success "CloudFront distribution created: ${CF_DIST_ID}"

log_info "Creating UI config.json..."
cat > ~/environment/aiagent/src/main/resources/static/config.json << EOF
{
  "userPoolId": "${USER_POOL_ID}",
  "clientId": "${CLIENT_ID}",
  "apiEndpoint": "${API_ENDPOINT}"
}
EOF
log_success "config.json created"

log_info "Uploading UI files to S3..."
UI_DIR=~/environment/aiagent/src/main/resources/static
for file in ${UI_DIR}/*.html ${UI_DIR}/*.js ${UI_DIR}/*.css ${UI_DIR}/*.json ${UI_DIR}/*.svg; do
  if [ -f "${file}" ]; then
    filename=$(basename "${file}")
    case "${filename}" in
      *.html) CONTENT_TYPE="text/html" ;;
      *.js) CONTENT_TYPE="application/javascript" ;;
      *.css) CONTENT_TYPE="text/css" ;;
      *.json) CONTENT_TYPE="application/json" ;;
      *.svg) CONTENT_TYPE="image/svg+xml" ;;
    esac
    aws s3 cp "${file}" "s3://${UI_BUCKET}/${filename}" \
      --content-type "${CONTENT_TYPE}" --no-cli-pager > /dev/null
  fi
done
log_success "UI files uploaded"

log_info "Invalidating CloudFront cache..."
aws cloudfront create-invalidation \
  --distribution-id "${CF_DIST_ID}" \
  --paths "/*" \
  --no-cli-pager > /dev/null
log_success "Cache invalidated"

log_info "Waiting for CloudFront to become available..."
while true; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${CF_DOMAIN}" || echo "000")
  echo "CloudFront HTTP status: ${HTTP_STATUS}"
  if [ "${HTTP_STATUS}" = "200" ]; then break; fi
  sleep 15
done

log_success "AgentCore deployment completed"
echo "✅ Success: AI Agent deployed to AgentCore"
echo "Runtime ID: ${RUNTIME_ID}"
echo "API Endpoint: ${API_ENDPOINT}"
echo "UI URL: https://${CF_DOMAIN}"
echo "Username: alice"
echo "Password: ${IDE_PASSWORD}"
