#!/bin/bash
set -e

echo "=============================================="
echo "01-create.sh - Create Spring Boot AI Agent"
echo "=============================================="

# Idempotency check
if [ -d ~/environment/aiagent ]; then
    echo "~/environment/aiagent already exists, skipping creation"
else
    cd ~/environment/

    curl -s https://start.spring.io/starter.zip \
      -d type=maven-project \
      -d language=java \
      -d packaging=jar \
      -d javaVersion=25 \
      -d bootVersion=4.0.2 \
      -d baseDir=aiagent \
      -d groupId=com.example \
      -d artifactId=agent \
      -d name=agent \
      -d description='AI agent with Spring AI and Amazon Bedrock' \
      -d dependencies=spring-ai-bedrock-converse,web,webflux,actuator \
      -o aiagent.zip

    unzip -q aiagent.zip
    rm aiagent.zip

    cd ~/environment/aiagent
    git init -q
    git add -A
    git commit -q -m "Initial Spring Boot project from start.spring.io"
fi

echo ""
echo "Project created at ~/environment/aiagent"
read -p "Press ENTER to continue..."

# --- Patch pom.xml: add agentcore BOM + runtime-starter ---

cd ~/environment/aiagent

# Add agentcore BOM to dependencyManagement (inside <dependencies>, after spring-ai-bom closing tag)
if ! grep -q "spring-ai-agentcore-bom" pom.xml; then
    sed -i '/<artifactId>spring-ai-bom<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t\t<dependency>\n\t\t\t\t<groupId>org.springaicommunity</groupId>\n\t\t\t\t<artifactId>spring-ai-agentcore-bom</artifactId>\n\t\t\t\t<version>1.0.0</version>\n\t\t\t\t<type>pom</type>\n\t\t\t\t<scope>import</scope>\n\t\t\t</dependency>
    }' pom.xml
fi

# Add runtime-starter dependency (after bedrock-converse)
if ! grep -q "spring-ai-agentcore-runtime-starter" pom.xml; then
    sed -i '/<artifactId>spring-ai-starter-model-bedrock-converse<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- AgentCore dependencies -->\n\t\t<dependency>\n\t\t\t<groupId>org.springaicommunity</groupId>\n\t\t\t<artifactId>spring-ai-agentcore-runtime-starter</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Write application.properties ---

cat > ~/environment/aiagent/src/main/resources/application.properties << 'EOF'
spring.application.name=agent
# Logging
logging.level.org.springframework.ai=DEBUG
logging.level.org.springaicommunity.agentcore=DEBUG
logging.level.com.example.agent=DEBUG
logging.pattern.console=%msg%n
# Amazon Bedrock Configuration
spring.ai.bedrock.aws.timeout=120s
spring.ai.bedrock.converse.chat.options.max-tokens=4096
spring.ai.bedrock.converse.chat.options.model=global.anthropic.claude-sonnet-4-5-20250929-v1:0
spring.ai.bedrock.converse.chat.options.temperature=0.7
EOF

# --- Write ChatService.java ---

cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/ChatService.java
package com.example.agent;

import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private final ChatClient chatClient;

    private static final String SYSTEM_PROMPT = """
        You are a helpful AI agent for travel and expense management.
        Be friendly, helpful, and concise in your responses.
        """;

    public ChatService(ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request) {
        return chatClient.prompt().user(request.prompt()).stream().content();
    }
}
EOF

# --- Copy static UI files ---

mkdir -p ~/environment/aiagent/src/main/resources/static
cp ~/java-on-aws/apps/java-spring-ai-agents/aiagent/src/main/resources/static/* \
    ~/environment/aiagent/src/main/resources/static/

echo ""
echo "Code added: ChatService + properties + UI"
read -p "Press ENTER to continue..."

# --- Commit and run ---

cd ~/environment/aiagent
git add -A
git commit -q -m "Add chat client with system prompt and web UI"

cd ~/environment/aiagent && ./mvnw spring-boot:run
