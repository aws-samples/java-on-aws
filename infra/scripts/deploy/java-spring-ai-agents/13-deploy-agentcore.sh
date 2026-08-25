#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "docker buildx, Python 3, ECR, AgentCore control-plane, S3, and CloudFront access"
init_context
load_state
require_cmd docker
require_cmd python3
require_cmd rsync
require_state MCP_URL COGNITO_USER_POOL_ID COGNITO_CLIENT_ID DB_PARAMETER_NAME DB_SECRET_ID
require_workshop_role aiagent-agentcore-runtime-role
ensure_ecr_repository aiagent
[[ -f "${AIAGENT_DIR}/pom.xml" ]] || die "AI-agent source not found. Run 01-setup.sh first."

BUILD_DIR="${WORK_DIR}/agentcore-build"
mkdir -p "${BUILD_DIR}"
rsync -a --delete "${AIAGENT_DIR}/" "${BUILD_DIR}/" --exclude .git --exclude target --exclude k8s
python3 - "${BUILD_DIR}/pom.xml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if "spring-ai-agentcore-bom" not in s:
    marker = "<dependencyManagement><dependencies>"
    bom = "<dependency><groupId>org.springaicommunity</groupId><artifactId>spring-ai-agentcore-bom</artifactId><version>2.1.0</version><type>pom</type><scope>import</scope></dependency>"
    if marker not in s:
        raise SystemExit("dependencyManagement marker not found")
    s = s.replace(marker, marker + bom, 1)
if "spring-ai-agentcore-runtime-starter" not in s:
    marker = "  <dependencies>"
    dep = "\n    <dependency><groupId>org.springaicommunity</groupId><artifactId>spring-ai-agentcore-runtime-starter</artifactId></dependency>"
    if marker not in s:
        raise SystemExit("dependencies marker not found")
    s = s.replace(marker, marker + dep, 1)
p.write_text(s)
PY
cat > "${BUILD_DIR}/src/main/java/com/example/agent/InvocationService.java" <<'EOF'
package com.example.agent;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
@Service
public class InvocationService {
    private static final int MAX_VERIFICATION_DOCUMENT_LENGTH = 4096;
    private final ChatService chatService;
    private final ObjectMapper objectMapper = new ObjectMapper();
    public InvocationService(ChatService chatService) { this.chatService = chatService; }
    @AgentCoreInvocation
    public Flux<String> handleInvocation(InvocationRequest request, AgentCoreContext context) throws Exception {
        String authorization = context.getHeader(AgentCoreHeaders.AUTHORIZATION);
        String jwt = authorization.replace("Bearer ", "");
        String payload = new String(Base64.getUrlDecoder().decode(jwt.split("\\.")[1]), StandardCharsets.UTF_8);
        JsonNode claims = objectMapper.readTree(payload);
        String username = claims.path("cognito:username").asText(claims.path("username").asText());
        if (request.verificationDocument() != null) {
            if (!"admin".equals(username)) throw new SecurityException("Only the workshop administrator can load verification knowledge");
            String document = request.verificationDocument();
            if (document.isBlank() || document.length() > MAX_VERIFICATION_DOCUMENT_LENGTH) {
                throw new IllegalArgumentException("Knowledge document must contain 1-4096 characters");
            }
            chatService.loadDocument(document);
            return Flux.just("Knowledge loaded");
        }
        String visitorId = claims.get("sub").asText().replace("-", "").substring(0, 25);
        return chatService.chat(request.prompt(), visitorId + ":" + claims.get("auth_time").asText());
    }
}
EOF
cat > "${BUILD_DIR}/Dockerfile" <<'EOF'
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-25-al2023 AS builder
COPY pom.xml pom.xml
COPY src src
RUN rm -rf src/main/resources/static && mvn -ntp clean package -DskipTests && mv target/agent-0.0.1-SNAPSHOT.jar app.jar
FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023
RUN yum install -y shadow-utils && yum clean all && groupadd --system spring -g 1000 && adduser spring -u 1000 -g 1000
COPY --from=builder app.jar /app.jar
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar"]
EOF

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${REGISTRY}/aiagent:alternative-agentcore"
aws_cli ecr get-login-password | docker login --username AWS --password-stdin "${REGISTRY}"
if ! docker buildx inspect java-spring-ai-agents-suite >/dev/null 2>&1; then
  docker buildx create --name java-spring-ai-agents-suite --driver docker-container >/dev/null
fi
docker buildx build --builder java-spring-ai-agents-suite --platform linux/arm64 -t "${ECR_URI}" --push "${BUILD_DIR}"
IMAGE_DIGEST=$(aws_cli ecr describe-images --repository-name aiagent --image-ids imageTag=alternative-agentcore \
  --query 'imageDetails[0].imageDigest' --output text)
CONTAINER_URI="${REGISTRY}/aiagent@${IMAGE_DIGEST}"
state_set AGENTCORE_IMAGE_URI "${CONTAINER_URI}"

VPC_ID=$(aws_cli ssm get-parameter --name workshop-vpc-id --query Parameter.Value --output text 2>/dev/null || true)
if is_none "${VPC_ID}"; then
  VPC_ID=$(aws_cli ec2 describe-vpcs --filters Name=tag:Name,Values=workshop-vpc --query 'Vpcs[0].VpcId' --output text)
fi
if [[ "${AWS_REGION}" == "us-east-1" ]]; then
  SUBNET_JSON=$(aws_cli ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
    "Name=tag:aws-cdk:subnet-type,Values=Private" "Name=availability-zone-id,Values=use1-az1,use1-az2,use1-az4" \
    --query 'Subnets[*].SubnetId' --output json)
else
  warn "AgentCore supported Availability Zones vary by Region; using all workshop private subnets for ${AWS_REGION}"
  SUBNET_JSON=$(aws_cli ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
    "Name=tag:aws-cdk:subnet-type,Values=Private" --query 'Subnets[*].SubnetId' --output json)
fi
[[ "$(jq length <<<"${SUBNET_JSON}")" -gt 0 ]] || die "No AgentCore-compatible private subnets found"
SG_ID=$(aws_cli ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=workshop-db-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)
[[ -n "${SG_ID}" && "${SG_ID}" != "None" ]] || die "Required workshop-db-sg was not found"
NETWORK=$(jq -nc --argjson subnets "${SUBNET_JSON}" --arg sg "${SG_ID}" '{networkMode:"VPC",networkModeConfig:{subnets:$subnets,securityGroups:[$sg]}}')
DISCOVERY_URL="https://cognito-idp.${AWS_REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}/.well-known/openid-configuration"
AUTHORIZER=$(jq -nc --arg url "${DISCOVERY_URL}" --arg client "${COGNITO_CLIENT_ID}" '{customJWTAuthorizer:{discoveryUrl:$url,allowedClients:[$client]}}')
HEADERS='{"requestHeaderAllowlist":["Authorization"]}'
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/aiagent-agentcore-runtime-role"
DB_URL=$(aws_cli ssm get-parameter --name "${DB_PARAMETER_NAME}" --query Parameter.Value --output text)
DB_JSON=$(aws_cli secretsmanager get-secret-value --secret-id "${DB_SECRET_ID}" --query SecretString --output text)
DB_USER=$(jq -r .username <<<"${DB_JSON}")
DB_PASS=$(jq -r .password <<<"${DB_JSON}")
DESIRED_ENV=$(jq -nc --arg db_url "${DB_URL}" --arg db_user "${DB_USER}" --arg db_pass "${DB_PASS}" --arg mcp "${MCP_URL}" \
  '{SPRING_DATASOURCE_URL:$db_url,SPRING_DATASOURCE_USERNAME:$db_user,SPRING_DATASOURCE_PASSWORD:$db_pass,SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL:$mcp}')
unset DB_JSON DB_USER DB_PASS

RUNTIME_NAME="aiagent-alternative"
RUNTIME_ID=$(aws_cli bedrock-agentcore-control list-agent-runtimes \
  --query "agentRuntimes[?agentRuntimeName=='${RUNTIME_NAME}'].agentRuntimeId | [0]" --output text)
if is_none "${RUNTIME_ID}"; then
  RUNTIME_ID=$(aws_cli bedrock-agentcore-control create-agent-runtime --agent-runtime-name "${RUNTIME_NAME}" --role-arn "${ROLE_ARN}" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${CONTAINER_URI}\"}}" \
    --network-configuration "${NETWORK}" --authorizer-configuration "${AUTHORIZER}" \
    --request-header-configuration "${HEADERS}" --environment-variables "${DESIRED_ENV}" \
    --tags "suite=${SUITE_OWNER}" --query agentRuntimeId --output text)
  state_set AGENTCORE_RUNTIME_CREATED true
else
  [[ "${AGENTCORE_RUNTIME_CREATED:-}" == true ]] || \
    die "Runtime ${RUNTIME_NAME} exists but is not recorded as suite-created in ${STATE_FILE}; refusing to update it"
  aws_cli bedrock-agentcore-control update-agent-runtime --agent-runtime-id "${RUNTIME_ID}" --role-arn "${ROLE_ARN}" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${CONTAINER_URI}\"}}" \
    --network-configuration "${NETWORK}" --authorizer-configuration "${AUTHORIZER}" \
    --request-header-configuration "${HEADERS}" --environment-variables "${DESIRED_ENV}" >/dev/null
fi
state_set AGENTCORE_RUNTIME_ID "${RUNTIME_ID}"

status=""
for i in {1..60}; do
  status=$(aws_cli bedrock-agentcore-control get-agent-runtime --agent-runtime-id "${RUNTIME_ID}" --query status --output text)
  [[ "${status}" == "READY" ]] && break
  [[ "${status}" == "FAILED" ]] && die "AgentCore Runtime entered FAILED state"
  log "Waiting for AgentCore Runtime: ${status} (${i}/60)"
  ((i == 60)) || sleep 10
done
[[ "${status}" == "READY" ]] || die "AgentCore Runtime did not become READY"
RUNTIME_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"
ENCODED_ARN=$(printf '%s' "${RUNTIME_ARN}" | jq -sRr @uri)
AIAGENT_ENDPOINT="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/${ENCODED_ARN}/invocations?qualifier=DEFAULT"
state_set AGENTCORE_LOG_GROUP "/aws/bedrock-agentcore/runtimes/${RUNTIME_ID}-DEFAULT"

UI_BUCKET="aiagent-ui-${ACCOUNT_ID}-${AWS_REGION}"
if aws_cli s3api head-bucket --bucket "${UI_BUCKET}" >/dev/null 2>&1; then
  if [[ "${AGENTCORE_UI_BUCKET_CREATED:-}" != true ]]; then
    tags=$(aws_cli s3api get-bucket-tagging --bucket "${UI_BUCKET}" --query 'TagSet' --output json 2>/dev/null || printf '[]')
    jq -e --arg owner "${SUITE_OWNER}" '.[] | select(.Key == "suite" and .Value == $owner)' >/dev/null <<<"${tags}" || \
      die "UI bucket ${UI_BUCKET} exists but is not owned by this suite"
  fi
  state_set AGENTCORE_UI_BUCKET_CREATED true
else
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws_cli s3api create-bucket --bucket "${UI_BUCKET}" >/dev/null
  else
    aws_cli s3api create-bucket --bucket "${UI_BUCKET}" --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
  aws_cli s3api put-public-access-block --bucket "${UI_BUCKET}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
  aws_cli s3api put-bucket-tagging --bucket "${UI_BUCKET}" --tagging "TagSet=[{Key=suite,Value=${SUITE_OWNER}}]" >/dev/null
  state_set AGENTCORE_UI_BUCKET_CREATED true
fi
state_set AGENTCORE_UI_BUCKET "${UI_BUCKET}"

OAI_COMMENT="${SUITE_OWNER}-aiagent-ui"
OAI_ID=$(aws_cli cloudfront list-cloud-front-origin-access-identities \
  --query "CloudFrontOriginAccessIdentityList.Items[?Comment=='${OAI_COMMENT}'].Id | [0]" --output text)
if is_none "${OAI_ID}"; then
  OAI_ID=$(aws_cli cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config "CallerReference=${SUITE_OWNER}-$(date +%s),Comment=${OAI_COMMENT}" \
    --query CloudFrontOriginAccessIdentity.Id --output text)
  state_set AGENTCORE_OAI_CREATED true
else
  state_set AGENTCORE_OAI_CREATED true
fi
state_set AGENTCORE_OAI_ID "${OAI_ID}"
OAI_CANONICAL=$(aws_cli cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" \
  --query CloudFrontOriginAccessIdentity.S3CanonicalUserId --output text)
POLICY=$(jq -nc --arg user "${OAI_CANONICAL}" --arg bucket "${UI_BUCKET}" '{Version:"2012-10-17",Statement:[{Effect:"Allow",Principal:{CanonicalUser:$user},Action:"s3:GetObject",Resource:("arn:aws:s3:::"+$bucket+"/*")}]}' )
aws_cli s3api put-bucket-policy --bucket "${UI_BUCKET}" --policy "${POLICY}"

DIST_COMMENT="${SUITE_OWNER}-aiagent-ui"
DIST_ID=$(aws_cli cloudfront list-distributions --query "DistributionList.Items[?Comment=='${DIST_COMMENT}'].Id | [0]" --output text)
ORIGIN_DOMAIN="${UI_BUCKET}.s3.${AWS_REGION}.amazonaws.com"
if is_none "${DIST_ID}"; then
  DIST_FILE="${WORK_DIR}/cloudfront-create.json"
  jq -n --arg caller "${SUITE_OWNER}-$(date +%s)" --arg comment "${DIST_COMMENT}" --arg bucket "${UI_BUCKET}" \
    --arg domain "${ORIGIN_DOMAIN}" --arg oai "origin-access-identity/cloudfront/${OAI_ID}" '{CallerReference:$caller,Comment:$comment,Enabled:true,DefaultRootObject:"index.html",Origins:{Quantity:1,Items:[{Id:("S3-"+$bucket),DomainName:$domain,S3OriginConfig:{OriginAccessIdentity:$oai}}]},DefaultCacheBehavior:{TargetOriginId:("S3-"+$bucket),ViewerProtocolPolicy:"redirect-to-https",AllowedMethods:{Quantity:2,Items:["GET","HEAD"],CachedMethods:{Quantity:2,Items:["GET","HEAD"]}},ForwardedValues:{QueryString:false,Cookies:{Forward:"none"}},MinTTL:0,DefaultTTL:300,MaxTTL:86400,Compress:true},CustomErrorResponses:{Quantity:1,Items:[{ErrorCode:403,ResponsePagePath:"/index.html",ResponseCode:"200",ErrorCachingMinTTL:10}]},PriceClass:"PriceClass_100"}' > "${DIST_FILE}"
  created=$(aws_cli cloudfront create-distribution --distribution-config "file://${DIST_FILE}")
  DIST_ID=$(jq -r '.Distribution.Id' <<<"${created}")
  state_set AGENTCORE_DISTRIBUTION_CREATED true
else
  state_set AGENTCORE_DISTRIBUTION_CREATED true
  current_file="${WORK_DIR}/cloudfront-current.json"
  desired_file="${WORK_DIR}/cloudfront-update.json"
  aws_cli cloudfront get-distribution-config --id "${DIST_ID}" > "${current_file}"
  etag=$(jq -r .ETag "${current_file}")
  jq --arg comment "${DIST_COMMENT}" --arg bucket "${UI_BUCKET}" --arg domain "${ORIGIN_DOMAIN}" \
    --arg oai "origin-access-identity/cloudfront/${OAI_ID}" '.DistributionConfig | .Comment=$comment | .Enabled=true | .DefaultRootObject="index.html" | .Origins={Quantity:1,Items:[{Id:("S3-"+$bucket),DomainName:$domain,S3OriginConfig:{OriginAccessIdentity:$oai}}]} | .DefaultCacheBehavior.TargetOriginId=("S3-"+$bucket)' "${current_file}" > "${desired_file}"
  aws_cli cloudfront update-distribution --id "${DIST_ID}" --if-match "${etag}" --distribution-config "file://${desired_file}" >/dev/null
fi
state_set AGENTCORE_DISTRIBUTION_ID "${DIST_ID}"

cat > "${AIAGENT_DIR}/src/main/resources/static/config.json" <<EOF
{
  "userPoolId": "${COGNITO_USER_POOL_ID}",
  "clientId": "${COGNITO_CLIENT_ID}",
  "region": "${AWS_REGION}",
  "apiEndpoint": "${AIAGENT_ENDPOINT}"
}
EOF
aws_cli s3 sync "${AIAGENT_DIR}/src/main/resources/static/" "s3://${UI_BUCKET}/" --delete --only-show-errors
aws_cli cloudfront create-invalidation --distribution-id "${DIST_ID}" --paths '/*' >/dev/null

cf_status=""
for i in {1..60}; do
  cf_status=$(aws_cli cloudfront get-distribution --id "${DIST_ID}" --query Distribution.Status --output text)
  [[ "${cf_status}" == "Deployed" ]] && break
  log "Waiting for CloudFront distribution: ${cf_status} (${i}/60)"
  ((i == 60)) || sleep 15
done
[[ "${cf_status}" == "Deployed" ]] || die "CloudFront distribution did not deploy"
CF_DOMAIN=$(aws_cli cloudfront get-distribution --id "${DIST_ID}" --query Distribution.DomainName --output text)
wait_for_http_status "AgentCore UI" "https://${CF_DOMAIN}" '^(200)$' 20 10
state_set AGENTCORE_UI_ENDPOINT "https://${CF_DOMAIN}"
state_set ACTIVE_TARGET agentcore
state_set AIAGENT_ENDPOINT "${AIAGENT_ENDPOINT}"
log "AgentCore Runtime created or updated: ${RUNTIME_ID}"
log "AgentCore UI created or updated: https://${CF_DOMAIN}"
