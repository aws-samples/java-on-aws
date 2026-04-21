#!/bin/bash
set -e

echo "=============================================="
echo "02-memory.sh - Add AgentCore Memory"
echo "=============================================="

cd ~/environment/aiagent

# --- Add env vars ---

source ~/demo-full/.envrc 2>/dev/null || true

# Extract memory ID from demo-full application.properties
MEMORY_ID=$(grep "agentcore.memory.memory-id" ~/demo-full/aiagent/src/main/resources/application.properties | cut -d= -f2)

if [ -z "$MEMORY_ID" ]; then
    echo "Error: Could not find memory-id in ~/demo-full/aiagent/src/main/resources/application.properties"
    exit 1
fi

# --- Add memory dependency to pom.xml ---

if ! grep -q "spring-ai-agentcore-memory" pom.xml; then
    sed -i '/<artifactId>spring-ai-agentcore-runtime-starter<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- AgentCore Memory dependencies -->\n\t\t<dependency>\n\t\t\t<groupId>org.springaicommunity</groupId>\n\t\t\t<artifactId>spring-ai-agentcore-memory</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Add memory properties ---

if ! grep -q "agentcore.memory.memory-id" src/main/resources/application.properties; then
    cat >> src/main/resources/application.properties << EOF

# AgentCore Memory
agentcore.memory.memory-id=${MEMORY_ID}
agentcore.memory.long-term.auto-discovery=true
EOF
fi

# --- Update ChatService.java ---

cat <<'EOF' > src/main/java/com/example/agent/ChatService.java
package com.example.agent;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springaicommunity.agentcore.memory.longterm.AgentCoreMemory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;

    private static final String SYSTEM_PROMPT = """
        You are a helpful AI agent for travel and expense management.
        Be friendly, helpful, and concise in your responses.
        """;

    public ChatService(AgentCoreMemory agentCoreMemory,
                       ChatClient.Builder chatClientBuilder) {

        List<Advisor> advisors = new ArrayList<>();

        // Memory (STM + LTM)
        advisors.addAll(agentCoreMemory.advisors);
        logger.info("Memory enabled: {} advisors", agentCoreMemory.advisors.size());

        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
        return chat(request.prompt(), getConversationId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
        return chatClient.prompt().user(prompt)
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            .stream().content();
    }

    private String getConversationId(AgentCoreContext context) {
        return context.getHeader(AgentCoreHeaders.SESSION_ID);
    }
}
EOF

echo ""
echo "Memory added: dependency + properties + ChatService updated"
read -p "Press ENTER to continue..."

git add -A
git commit -q -m "Add AgentCore Memory (STM + LTM)"

cd ~/environment/aiagent && ./mvnw spring-boot:run
