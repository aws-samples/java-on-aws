package com.example.agent;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
// >>
import org.springaicommunity.agentcore.artifacts.ArtifactStore;
import org.springaicommunity.agentcore.artifacts.GeneratedFile;
import org.springaicommunity.agentcore.artifacts.SessionConstants;
import org.springaicommunity.agentcore.browser.BrowserArtifacts;
// <<
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springaicommunity.agentcore.memory.longterm.AgentCoreMemory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.prompt.PromptTemplate;
// >>
import org.springframework.ai.tool.ToolCallbackProvider;
// <<
import org.springframework.ai.vectorstore.VectorStore;
// >>
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
// <<
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;
    // >> The artifact stores keep screenshots and generated files per conversation; `ArtifactLinks` uploads them to S3
    private final ArtifactStore<GeneratedFile> browserArtifactStore;
    private final ArtifactLinks artifactLinks;
    // <<

    private static final String SYSTEM_PROMPT = """
        You are the travel and expense assistant of the company. You help employees plan business trips,
        follow the travel and expense policies, and keep track of their trips and expenses.

        Rules:
        - Focus on business travel and expenses.
        - Ask for missing details such as dates, origin, or destination instead of guessing them.
        - Do not invent policy rules; say so when you are not sure.

        Format:
        - Be friendly and concise.
        - Use tables to compare options.
        """;

    public ChatService(AgentCoreMemory agentCoreMemory,
        VectorStore kbVectorStore,
        WebGroundingTools webGroundingTools,
        ContextAdvisor contextAdvisor,
        // >> The browser tools, its artifact store, the S3 artifact links, and the travel portal URL
        @Qualifier("browserToolCallbackProvider") ToolCallbackProvider browserTools,
        @Qualifier("browserArtifactStore") ArtifactStore<GeneratedFile> browserArtifactStore,
        ArtifactLinks artifactLinks,
        @Value("${app.portal-url}") String portalUrl,
        // <<
        ChatClient.Builder chatClientBuilder) {

        List<Advisor> advisors = new ArrayList<>();

        // Memory (STM + LTM)
        advisors.addAll(agentCoreMemory.advisors);
        logger.info("Memory enabled: {} advisors", agentCoreMemory.advisors.size());

        // Knowledge Base (RAG)
        advisors.add(QuestionAnswerAdvisor.builder(kbVectorStore)
            .promptTemplate(PromptTemplate.builder().template("""
                {query}

                The following documents may be relevant as reference material:
                {question_answer_context}
                """).build())
            .build());
        logger.info("KB RAG enabled");

        // ContextAdvisor
        advisors.add(contextAdvisor);
        logger.info("Context Advisor enabled");

        // Tools
        List<Object> localTools = new ArrayList<>();
        localTools.add(webGroundingTools);
        logger.info("Web Grounding enabled");

        // >> Keep the artifact store and links for `appendScreenshots()`; the browser tools go into the tool callback providers
        // Browser
        this.browserArtifactStore = browserArtifactStore;
        this.artifactLinks = artifactLinks;

        // Tool Callback Providers
        List<ToolCallbackProvider> toolCallbackProviders = new ArrayList<>();
        toolCallbackProviders.add(browserTools);
        logger.info("Browser enabled");
        // <<

        this.chatClient = chatClientBuilder
            // >> Tell the model where to find flight and hotel offers
            .defaultSystem(SYSTEM_PROMPT + "\nFlight and hotel offers: the corporate travel portal " + portalUrl + "\n")
            // <<
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            .defaultTools(localTools.toArray())
            // >> `.defaultTools()` also accepts `ToolCallbackProvider` instances; the calls accumulate
            .defaultTools(toolCallbackProviders.toArray())
            // <<
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
        return chat(request.prompt(), getConversationId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
        return chatClient.prompt().user(prompt)
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            // >> Append screenshots after the answer; the session ID goes into the Reactor context for the tools
            .stream().content()
            .concatWith(Flux.defer(() -> appendScreenshots(sessionId)))
            .contextWrite(ctx -> ctx.put(SessionConstants.SESSION_ID_KEY, sessionId));
            // <<
    }

    private String getConversationId(AgentCoreContext context) {
        return context.getHeader(AgentCoreHeaders.SESSION_ID);
    }

    // >> Format screenshots as markdown images with presigned S3 links
    private Flux<String> appendScreenshots(String sessionId) {
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
                .append(artifactLinks.link(screenshot))
                .append(")");
        }
        return sb.toString();
    }
    // <<
}
