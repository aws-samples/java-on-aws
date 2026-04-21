#!/bin/bash
set -e

echo "=============================================="
echo "03-kb.sh - Add Bedrock Knowledge Base (RAG)"
echo "=============================================="

cd ~/environment/aiagent

# --- Get KB ID from demo-full ---

KB_ID=$(grep "spring.ai.vectorstore.bedrock-knowledge-base.knowledge-base-id" ~/demo-full/aiagent/src/main/resources/application.properties | cut -d= -f2)

if [ -z "$KB_ID" ]; then
    echo "Error: Could not find knowledge-base-id in ~/demo-full/aiagent/src/main/resources/application.properties"
    exit 1
fi

# --- Add KB dependencies to pom.xml ---

if ! grep -q "spring-ai-starter-vector-store-bedrock-knowledgebase" pom.xml; then
    sed -i '/<artifactId>spring-ai-agentcore-memory<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- Knowledge Base (RAG) -->\n\t\t<dependency>\n\t\t\t<groupId>org.springframework.ai</groupId>\n\t\t\t<artifactId>spring-ai-starter-vector-store-bedrock-knowledgebase</artifactId>\n\t\t</dependency>\n\t\t<dependency>\n\t\t\t<groupId>org.springframework.ai</groupId>\n\t\t\t<artifactId>spring-ai-advisors-vector-store</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Add KB property ---

if ! grep -q "spring.ai.vectorstore.bedrock-knowledge-base.knowledge-base-id" src/main/resources/application.properties; then
    cat >> src/main/resources/application.properties << EOF

# Knowledge Base
spring.ai.vectorstore.bedrock-knowledge-base.knowledge-base-id=${KB_ID}
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
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.prompt.PromptTemplate;
import org.springframework.ai.vectorstore.VectorStore;
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
                       VectorStore kbVectorStore,
                       ChatClient.Builder chatClientBuilder) {

        List<Advisor> advisors = new ArrayList<>();

        // Memory (STM + LTM)
        advisors.addAll(agentCoreMemory.advisors);
        logger.info("Memory enabled: {} advisors", agentCoreMemory.advisors.size());

        // Knowledge Base (RAG)
        if (kbVectorStore != null) {
            advisors.add(QuestionAnswerAdvisor.builder(kbVectorStore)
                .promptTemplate(PromptTemplate.builder().template("""
                    {query}

                    The following documents may be relevant as reference material:
                    {question_answer_context}
                    """).build())
                .build());
            logger.info("KB RAG enabled");
        }

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
echo "Knowledge Base added: dependencies + property + ChatService updated"
echo ""
echo "NOTE: Default QuestionAnswerAdvisor template says:"
echo "  'Given the context information and no prior knowledge, answer the query.'"
echo "  We override it to treat KB docs as supplementary, not restrictive."
read -p "Press ENTER to continue..."

git add -A
git commit -q -m "Add Bedrock Knowledge Base (RAG)"

cd ~/environment/aiagent && ./mvnw spring-boot:run
