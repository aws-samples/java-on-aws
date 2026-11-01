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
import org.springaicommunity.agentcore.memory.longterm.AgentCoreMemory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.prompt.PromptTemplate;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.ai.vectorstore.SearchRequest;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;
    private final ArtifactStore<GeneratedFile> browserArtifactStore;
    private final ArtifactStore<GeneratedFile> codeInterpreterArtifactStore;
    private final ArtifactLinks artifactLinks;
    private final ComplianceTools complianceTools;
    // >> The guardrail helper checks web pages and masks the prompt
    private final Guardrail guardrail;
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
        ContextAdvisor contextAdvisor,
        @Qualifier("browserToolCallbackProvider") ToolCallbackProvider browserTools,
        @Qualifier("browserArtifactStore") ArtifactStore<GeneratedFile> browserArtifactStore,
        ArtifactLinks artifactLinks,
        @Value("${app.portal-url}") String portalUrl,
        @Qualifier("codeInterpreterToolCallbackProvider") ToolCallbackProvider codeInterpreterTools,
        @Qualifier("codeInterpreterArtifactStore") ArtifactStore<GeneratedFile> codeInterpreterArtifactStore,
        @Qualifier("mcpToolCallbacks") ToolCallbackProvider mcpTools,
        ComplianceTools complianceTools,
        // >> Inject the guardrail helper
        Guardrail guardrail,
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
            .searchRequest(SearchRequest.builder().topK(5).build())
            .build());
        logger.info("KB RAG enabled");

        // ContextAdvisor
        advisors.add(contextAdvisor);
        logger.info("Context Advisor enabled");

        // Browser
        this.browserArtifactStore = browserArtifactStore;
        this.artifactLinks = artifactLinks;

        // Tool Callback Providers
        List<ToolCallbackProvider> toolCallbackProviders = new ArrayList<>();
        // >> Check the page text that `browseUrl` and `evaluateScript` return before the model reads it
        this.guardrail = guardrail;
        toolCallbackProviders.add(guardrail.guard(browserTools, "browseUrl", "evaluateScript"));
        // <<
        logger.info("Browser enabled");

        // Code Interpreter
        this.codeInterpreterArtifactStore = codeInterpreterArtifactStore;
        toolCallbackProviders.add(codeInterpreterTools);
        logger.info("Code Interpreter enabled");

        // MCP Tools
        toolCallbackProviders.add(mcpTools);
        logger.info("MCP tools enabled");

        // Compliance auditor (agent as tool)
        this.complianceTools = complianceTools;
        if (complianceTools.enabled()) {
            toolCallbackProviders.add(MethodToolCallbackProvider.builder().toolObjects(complianceTools).build());
            logger.info("Compliance auditor enabled");
        }

        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT + "\nFlight and hotel offers: the corporate travel portal " + portalUrl + "\n")
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            .defaultTools(toolCallbackProviders.toArray())
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
        return chat(request.prompt(), getConversationId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
        // >> Mask payment data before the memory advisors store the prompt
        return chatClient.prompt().user(guardrail.maskPii(prompt))
        // <<
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            .stream().content()
            .concatWith(Flux.defer(() -> appendGeneratedFiles(sessionId)))
            .concatWith(Flux.defer(() -> appendScreenshots(sessionId)))
            .concatWith(Flux.defer(() -> appendAuditReports(sessionId)))
            .contextWrite(ctx -> ctx.put(SessionConstants.SESSION_ID_KEY, sessionId));
    }

    private String getConversationId(AgentCoreContext context) {
        return ConversationIdResolver.resolve(context);
    }

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

    private Flux<String> appendGeneratedFiles(String sessionId) {
        List<GeneratedFile> files = codeInterpreterArtifactStore.retrieve(sessionId);
        if (files == null || files.isEmpty()) {
            return Flux.empty();
        }
        String markdown = formatFilesAsMarkdown(files);
        if (markdown.isEmpty()) {
            return Flux.empty();
        }
        return Flux.just(markdown);
    }

    private String formatFilesAsMarkdown(List<GeneratedFile> files) {
        StringBuilder sb = new StringBuilder();
        for (GeneratedFile file : files) {
            if (file.name().equals("package.json") || file.name().equals("package-lock.json")) {
                continue;
            }
            if (file.isImage()) {
                sb.append("\n\n![").append(file.name()).append("](")
                    .append(artifactLinks.link(file)).append(")");
            } else {
                sb.append("\n\n[Download ").append(file.name()).append("](")
                    .append(artifactLinks.link(file)).append(")");
            }
        }
        return sb.toString();
    }

    private Flux<String> appendAuditReports(String sessionId) {
        StringBuilder sb = new StringBuilder();
        for (String link : complianceTools.takeReportLinks(sessionId)) {
            sb.append("\n\n[Download audit-report.md](").append(link).append(")");
        }
        return sb.isEmpty() ? Flux.empty() : Flux.just(sb.toString());
    }
}
