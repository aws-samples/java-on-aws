#!/bin/bash
set -e

echo "=============================================="
echo "04-tools.sh - Add ContextAdvisor + WebGroundingTools"
echo "=============================================="

cd ~/environment/aiagent

# --- Add AWS SDK BOM to dependencyManagement (after agentcore-bom) ---

if ! grep -q "software.amazon.awssdk" pom.xml; then
    sed -i '/<artifactId>spring-ai-agentcore-bom<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t\t<dependency>\n\t\t\t\t<groupId>software.amazon.awssdk</groupId>\n\t\t\t\t<artifactId>bom</artifactId>\n\t\t\t\t<version>2.41.24</version>\n\t\t\t\t<type>pom</type>\n\t\t\t\t<scope>import</scope>\n\t\t\t</dependency>
    }' pom.xml
fi

# --- Add bedrockruntime dependency ---

if ! grep -q "bedrockruntime" pom.xml; then
    sed -i '/<artifactId>spring-ai-advisors-vector-store<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- Bedrock Runtime SDK for web grounding -->\n\t\t<dependency>\n\t\t\t<groupId>software.amazon.awssdk</groupId>\n\t\t\t<artifactId>bedrockruntime</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Write ContextAdvisor.java ---

cat <<'EOF' > src/main/java/com/example/agent/ContextAdvisor.java
package com.example.agent;

import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import org.springframework.ai.chat.client.ChatClientRequest;
import org.springframework.ai.chat.client.ChatClientResponse;
import org.springframework.ai.chat.client.advisor.api.AdvisorChain;
import org.springframework.ai.chat.client.advisor.api.BaseAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.stereotype.Component;

@Component
class ContextAdvisor implements BaseAdvisor {

    @Override
    public ChatClientRequest before(ChatClientRequest request, AdvisorChain advisorChain) {
        Prompt original = request.prompt();
        String timestamp = ZonedDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
        String conversationId = (String) request.context().get(ChatMemory.CONVERSATION_ID);
        String userId = conversationId != null ? conversationId.split(":")[0] : "unknown";

        List<Message> messages = new ArrayList<>(original.getInstructions());
        UserMessage userMsg = original.getUserMessage();
        if (userMsg != null) {
            messages.remove(userMsg);
            messages.add(new UserMessage("[Current date and time: " + timestamp + "]"));
            messages.add(new UserMessage("[UserId: " + userId + "]\n" + userMsg.getText()));
        }

        Prompt augmented = new Prompt(messages, original.getOptions());
        return request.mutate().prompt(augmented).build();
    }

    @Override
    public ChatClientResponse after(ChatClientResponse response, AdvisorChain advisorChain) {
        return response;
    }

    @Override
    public int getOrder() {
        return 0;
    }
}
EOF

# --- Write WebGroundingTools.java ---

cat <<'EOF' > src/main/java/com/example/agent/WebGroundingTools.java
package com.example.agent;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import jakarta.annotation.PreDestroy;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.*;

@Service
public class WebGroundingTools {

    private static final Logger logger = LoggerFactory.getLogger(WebGroundingTools.class);

    private final BedrockRuntimeClient bedrockClient;

    private final String modelId;

    public WebGroundingTools(@Value("${app.ai.web-grounding.model:us.amazon.nova-2-lite-v1:0}") String modelId) {
        this.modelId = modelId;
        this.bedrockClient = BedrockRuntimeClient.builder().build();
        logger.info("WebGroundingTools: model={}", modelId);
    }

    @PreDestroy
    public void close() {
        if (bedrockClient != null) {
            bedrockClient.close();
        }
    }

    @Tool(description = "Search the web for current information. Use for news, real-time data, or facts needing verification.")
    public String searchWeb(@ToolParam(description = "Search query") String query) {
        logger.info("Web search: {}", query);
        try {
            var response = bedrockClient.converse(ConverseRequest.builder()
                .modelId(modelId)
                .messages(Message.builder().role(ConversationRole.USER).content(ContentBlock.fromText(query)).build())
                .toolConfig(ToolConfiguration.builder()
                    .tools(software.amazon.awssdk.services.bedrockruntime.model.Tool
                        .fromSystemTool(SystemTool.builder().name("nova_grounding").build()))
                    .build())
                .build());

            return extractResponse(response);
        }
        catch (Exception e) {
            logger.error("Web search failed: {}", e.getMessage(), e);
            return "Web search failed. Try again later.";
        }
    }

    private String extractResponse(ConverseResponse response) {
        var result = new StringBuilder();
        var citations = new StringBuilder();

        logger.debug("Raw response: {}", response);

        if (response.output() != null && response.output().message() != null) {
            for (var block : response.output().message().content()) {
                if (block.text() != null) {
                    result.append(block.text());
                }
                if (block.citationsContent() != null && block.citationsContent().citations() != null) {
                    for (var citation : block.citationsContent().citations()) {
                        if (citation.location() != null && citation.location().web() != null) {
                            var url = citation.location().web().url();
                            if (url != null && !url.isEmpty()) {
                                citations.append("\n- ").append(url);
                            }
                        }
                    }
                }
            }
        }

        if (result.isEmpty()) {
            return "No results found.";
        }
        if (!citations.isEmpty()) {
            result.append("\n\nSources:").append(citations);
        }
        return result.toString();
    }

}
EOF

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
                       WebGroundingTools webGroundingTools,
                       ContextAdvisor contextAdvisor,
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

        // ContextAdvisor
        advisors.add(contextAdvisor);
        logger.info("Context Advisor enabled");

        // Tools
        List<Object> localTools = new ArrayList<>();
        if (webGroundingTools != null) {
            localTools.add(webGroundingTools);
            logger.info("Web Grounding enabled");
        }

        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            .defaultTools(localTools.toArray())
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
echo "Tools added: ContextAdvisor + WebGroundingTools + ChatService updated"
read -p "Press ENTER to continue..."

git add -A
git commit -q -m "Add ContextAdvisor and WebGroundingTools"

cd ~/environment/aiagent && ./mvnw spring-boot:run
