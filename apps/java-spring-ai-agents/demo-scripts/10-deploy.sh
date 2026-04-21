#!/bin/bash
set -e

echo "=============================================="
echo "10-deploy.sh - Add Security + Deploy to Runtime"
echo "=============================================="

cd ~/environment/aiagent

# --- Get env vars from demo-full ---

source ~/demo-full/.envrc 2>/dev/null || true

if [ -z "$AIAGENT_USER_POOL_ID" ] || [ -z "$AIAGENT_RUNTIME_ID" ]; then
    echo "Error: Missing AIAGENT_USER_POOL_ID or AIAGENT_RUNTIME_ID in ~/demo-full/.envrc"
    exit 1
fi

AWS_REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)

# --- Add security dependency to pom.xml ---

if ! grep -q "spring-boot-starter-oauth2-resource-server" pom.xml; then
    sed -i '/<artifactId>spring-ai-agentcore-runtime-starter<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- Security - OAuth2 Resource Server for JWT validation -->\n\t\t<dependency>\n\t\t\t<groupId>org.springframework.boot</groupId>\n\t\t\t<artifactId>spring-boot-starter-oauth2-resource-server</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Add headless profile to pom.xml ---

if ! grep -q "<id>headless</id>" pom.xml; then
    sed -i '/<\/build>/a \
\n\t<profiles>\n\t\t<profile>\n\t\t\t<id>headless</id>\n\t\t\t<build>\n\t\t\t\t<resources>\n\t\t\t\t\t<resource>\n\t\t\t\t\t\t<directory>src/main/resources</directory>\n\t\t\t\t\t\t<excludes>\n\t\t\t\t\t\t\t<exclude>static/**</exclude>\n\t\t\t\t\t\t</excludes>\n\t\t\t\t\t</resource>\n\t\t\t\t</resources>\n\t\t\t</build>\n\t\t</profile>\n\t</profiles>
    ' pom.xml
fi

# --- Add security property ---

if ! grep -q "spring.security.oauth2.resourceserver.jwt.issuer-uri" src/main/resources/application.properties; then
    cat >> src/main/resources/application.properties << EOF

# Security
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://cognito-idp.${AWS_REGION}.amazonaws.com/${AIAGENT_USER_POOL_ID}
EOF
fi

# --- Write SecurityConfig.java ---

cat <<'EOF' > src/main/java/com/example/agent/SecurityConfig.java
package com.example.agent;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri:}")
    private String issuerUri;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.disable());
        http.authorizeHttpRequests(auth -> auth
            .requestMatchers("/", "/*.js", "/*.css", "/*.json", "/*.svg", "/*.html").permitAll()
            .requestMatchers("/actuator/**").permitAll()
        );

        if (issuerUri != null && !issuerUri.isBlank()) {
            http.authorizeHttpRequests(auth -> auth
                    .requestMatchers("/invocations").authenticated()
                    .anyRequest().permitAll())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        } else {
            http.authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        }

        return http.build();
    }
}
EOF

# --- Write ConversationIdResolver.java ---

cat <<'EOF' > src/main/java/com/example/agent/ConversationIdResolver.java
package com.example.agent;

import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.Base64;
import java.util.UUID;

/**
 * Utility for extracting conversation ID from AgentCore context.
 * Format: userId:sessionId (authenticated) or sessionId (anonymous)
 */
public final class ConversationIdResolver {

    private static final Logger logger = LoggerFactory.getLogger(ConversationIdResolver.class);
    private static final JsonMapper jsonMapper = JsonMapper.builder().build();

    private ConversationIdResolver() {}

    public static String resolve(AgentCoreContext context) {
        String sessionId = context.getHeader(AgentCoreHeaders.SESSION_ID);
        if (sessionId == null || sessionId.isBlank()) {
            sessionId = UUID.randomUUID().toString();
        }

        String authHeader = context.getHeader(AgentCoreHeaders.AUTHORIZATION);
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            try {
                String jwt = authHeader.substring(7);
                String payload = new String(Base64.getUrlDecoder().decode(jwt.split("\\.")[1]));
                JsonNode claims = jsonMapper.readTree(payload);
                String userId = claims.get("sub").asString();
                return userId + ":" + sessionId;
            } catch (Exception e) {
                logger.debug("JWT parsing failed, using sessionId only", e);
            }
        }

        return sessionId;
    }
}
EOF

# --- Update ChatService getConversationId to use ConversationIdResolver ---

sed -i 's/return context.getHeader(AgentCoreHeaders.SESSION_ID);/return ConversationIdResolver.resolve(context);/' \
    src/main/java/com/example/agent/ChatService.java

echo ""
echo "Security + ConversationIdResolver + headless profile added"

# --- Generate config.json for UI ---

cat > src/main/resources/static/config.json << EOF
{
  "userPoolId": "${AIAGENT_USER_POOL_ID}",
  "clientId": "${AIAGENT_CLIENT_ID}",
  "apiEndpoint": "${AIAGENT_ENDPOINT}",
  "enableAttachments": true
}
EOF

read -p "Press ENTER to continue..."

git add -A
git commit -q -m "Add security, ConversationIdResolver, headless profile"

# --- Build and deploy ---

echo ""
echo "Building and deploying to AgentCore Runtime..."

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent"

aws ecr get-login-password --region ${AWS_REGION} --no-cli-pager | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Building container image..."
mvn -ntp spring-boot:build-image \
    -Pheadless \
    -DskipTests \
    -Dspring-boot.build-image.imageName="${ECR_URI}:latest" \
    -Dspring-boot.build-image.imagePlatform=linux/arm64

echo "Pushing container image to ECR..."
docker push "${ECR_URI}:latest"

echo "Updating AgentCore Runtime..."
aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-id "${AIAGENT_RUNTIME_ID}" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-runtime-role" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
    --network-configuration "{\"networkMode\":\"VPC\",\"networkModeConfig\":{\"subnets\":[\"${SUBNET_ID}\"],\"securityGroups\":[\"${SG_ID}\"]}}" \
    --authorizer-configuration "{\"customJWTAuthorizer\":{\"discoveryUrl\":\"${AIAGENT_DISCOVERY_URL}\",\"allowedClients\":[\"${AIAGENT_CLIENT_ID}\"]}}" \
    --request-header-configuration '{"requestHeaderAllowlist":["Authorization"]}' \
    --region ${AWS_REGION} \
    --no-cli-pager

echo -n "Waiting for runtime"
while [ "$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${AIAGENT_RUNTIME_ID}" --region ${AWS_REGION} \
    --no-cli-pager --query 'status' --output text)" != "READY" ]; do
    echo -n "."; sleep 5
done && echo " READY"

echo ""
echo "=============================================="
echo "Deploy complete!"
echo "=============================================="
echo "UI URL: https://${UI_DOMAIN}"
echo "Users: admin, alice, bob"
echo "Password: ${IDE_PASSWORD}"
