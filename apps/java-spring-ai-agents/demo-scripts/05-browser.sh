#!/bin/bash
set -e

echo "=============================================="
echo "06-browser.sh - Add AgentCore Browser"
echo "=============================================="

cd ~/environment/aiagent

# --- Add browser dependency to pom.xml ---

if ! grep -q "spring-ai-agentcore-browser" pom.xml; then
    sed -i '/<artifactId>bedrockruntime<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- AgentCore Browser -->\n\t\t<dependency>\n\t\t\t<groupId>org.springaicommunity</groupId>\n\t\t\t<artifactId>spring-ai-agentcore-browser</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Add browser properties ---

if ! grep -q "agentcore.browser" src/main/resources/application.properties; then
    cat >> src/main/resources/application.properties << 'EOF'

# AgentCore Browser - tool descriptions
agentcore.browser.browse-url-description=Browse a web page and extract its text content. Returns the page title and body text. Use this to read and extract data from websites. For interactive sites, combine with fillForm and clickElement to navigate, then call browseUrl again to read the results.
agentcore.browser.screenshot-description=Take a screenshot of a web page for the user to see. Does NOT return page content to you. Use browseUrl to extract data first, then takeScreenshot for visual evidence.
EOF
fi

# --- Add PLAYWRIGHT env var ---

if ! grep -q "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD" ~/environment/.envrc 2>/dev/null; then
    echo "export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1" >> ~/environment/.envrc
fi

# --- Update ChatService.java ---

cat <<'EOF' > src/main/java/com/example/agent/ChatService.java
package com.example.agent;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springaicommunity.agentcore.artifacts.ArtifactStore;
import org.springaicommunity.agentcore.artifacts.GeneratedFile;
import org.springaicommunity.agentcore.artifacts.SessionConstants;
import org.springaicommunity.agentcore.browser.BrowserArtifacts;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springaicommunity.agentcore.memory.longterm.AgentCoreMemory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.prompt.PromptTemplate;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;

    private final ArtifactStore<GeneratedFile> browserArtifactStore;

    private static final String SYSTEM_PROMPT = """
        You are a helpful AI agent for travel and expense management.
        Be friendly, helpful, and concise in your responses.
        """;

    public ChatService(AgentCoreMemory agentCoreMemory,
                       VectorStore kbVectorStore,
                       WebGroundingTools webGroundingTools,
                       ContextAdvisor contextAdvisor,
                       @Qualifier("browserToolCallbackProvider") ToolCallbackProvider browserTools,
                       @Qualifier("browserArtifactStore") ArtifactStore<GeneratedFile> browserArtifactStore,
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

        // Browser
        this.browserArtifactStore = browserArtifactStore;

        // Tool Callback Providers
        List<ToolCallbackProvider> toolCallbackProviders = new ArrayList<>();
        if (browserTools != null) {
            toolCallbackProviders.add(browserTools);
            logger.info("Browser enabled");
        }

        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            .defaultTools(localTools.toArray())
            .defaultToolCallbacks(toolCallbackProviders.toArray(new ToolCallbackProvider[0]))
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
        return chat(request.prompt(), getConversationId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
        return chatClient.prompt().user(prompt)
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            .stream().content()
            .concatWith(Flux.defer(() -> appendScreenshots(sessionId)))
            .contextWrite(ctx -> ctx.put(SessionConstants.SESSION_ID_KEY, sessionId));
    }

    private String getConversationId(AgentCoreContext context) {
        return context.getHeader(AgentCoreHeaders.SESSION_ID);
    }

    private Flux<String> appendScreenshots(String sessionId) {
        if (browserArtifactStore == null) {
            return Flux.empty();
        }
        List<GeneratedFile> screenshots = browserArtifactStore.retrieve(sessionId);
        if (screenshots == null || screenshots.isEmpty()) {
            return Flux.empty();
        }
        return Flux.just(formatScreenshotsAsMarkdown(screenshots));
    }

    private String formatScreenshotsAsMarkdown(List<GeneratedFile> screenshots) {
        StringBuilder sb = new StringBuilder();
        for (GeneratedFile screenshot : screenshots) {
            sb.append("\n\n![Screenshot of ")
                .append(BrowserArtifacts.url(screenshot).orElse("unknown"))
                .append("](")
                .append(screenshot.toDataUrl())
                .append(")");
        }
        return sb.toString();
    }
}
EOF

echo ""
echo "Browser added: dependency + properties + ChatService updated"
read -p "Press ENTER to continue..."

git add -A
git commit -q -m "Add AgentCore Browser with screenshots"

export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
cd ~/environment/aiagent && ./mvnw spring-boot:run
