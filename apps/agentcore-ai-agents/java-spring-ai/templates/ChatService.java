package com.example.agent;

@@+memory
import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
@@-
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
@@+browser
import org.springaicommunity.agentcore.artifacts.ArtifactStore;
import org.springaicommunity.agentcore.artifacts.GeneratedFile;
import org.springaicommunity.agentcore.artifacts.SessionConstants;
import org.springaicommunity.agentcore.browser.BrowserArtifacts;
@@-
@@+memory
import org.springaicommunity.agentcore.context.AgentCoreContext;
@@-
@@+memory
@@!deploy
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
@@-
@@+memory
import org.springaicommunity.agentcore.memory.longterm.AgentCoreMemory;
@@-
import org.springframework.ai.chat.client.ChatClient;
@@+memory
import org.springframework.ai.chat.client.advisor.api.Advisor;
@@-
@@+knowledge
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
@@-
@@+memory
import org.springframework.ai.chat.memory.ChatMemory;
@@-
@@+knowledge
import org.springframework.ai.chat.prompt.PromptTemplate;
@@-
@@+browser
import org.springframework.ai.tool.ToolCallbackProvider;
@@-
@@+agent-as-tool
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
@@-
@@+knowledge
import org.springframework.ai.vectorstore.SearchRequest;
import org.springframework.ai.vectorstore.VectorStore;
@@-
@@+browser
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
@@-
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

@@!identity
record ChatRequest(String prompt) {}
@@-
@@+identity The callback page sends the consent session as `oauthSession`
@@!document-processing
record ChatRequest(String prompt, String oauthSession) {}
@@-
@@+document-processing The UI sends an attached file as `fileName` and `fileBase64`
record ChatRequest(String prompt, String fileName, String fileBase64, String oauthSession) {}
@@-

@Service
public class ChatService {
@@+memory

    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);
@@-

    private final ChatClient chatClient;
@@+browser The artifact stores keep screenshots and generated files per conversation; `ArtifactLinks` uploads them to S3
    private final ArtifactStore<GeneratedFile> browserArtifactStore;
@@-
@@+code-interpreter
    private final ArtifactStore<GeneratedFile> codeInterpreterArtifactStore;
@@-
@@+browser The artifact stores keep screenshots and generated files per conversation; `ArtifactLinks` uploads them to S3
    private final ArtifactLinks artifactLinks;
@@-
@@+agent-as-tool The compliance auditor tool keeps the report links per conversation
    private final ComplianceTools complianceTools;
@@-
@@+guardrails The guardrail helper checks web pages and masks the prompt
    private final Guardrail guardrail;
@@-
@@+identity The calendar tool completes the user's consent
    private final CalendarTools calendarTools;
@@-
@@+document-processing The attachment handling uploads the file and adds it to the message
    private final Attachments attachments;
@@-
@@+policies The backoffice tools of the JWT Gateway, per user
    private final GatewayTools gatewayTools;
@@-
@@+persona The system prompt defines the persona of the AI agent

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
@@-

@@!memory
    public ChatService(ChatClient.Builder chatClientBuilder) {
@@-
@@+memory `AgentCoreMemory` provides the STM and LTM advisors in one bean
    public ChatService(AgentCoreMemory agentCoreMemory,
@@-
@@+knowledge `VectorStore` is auto-configured for the Bedrock Knowledge Base
        VectorStore kbVectorStore,
@@-
@@+tools Inject the web grounding tool and the context advisor
@@!mcp-client
        WebGroundingTools webGroundingTools,
@@-
@@+tools Inject the web grounding tool and the context advisor
        ContextAdvisor contextAdvisor,
@@-
@@+browser The browser tools, its artifact store, the S3 artifact links, and the travel portal URL
        @Qualifier("browserToolCallbackProvider") ToolCallbackProvider browserTools,
        @Qualifier("browserArtifactStore") ArtifactStore<GeneratedFile> browserArtifactStore,
        ArtifactLinks artifactLinks,
        @Value("${app.portal-url}") String portalUrl,
@@-
@@+code-interpreter The code interpreter tool and its artifact store
        @Qualifier("codeInterpreterToolCallbackProvider") ToolCallbackProvider codeInterpreterTools,
        @Qualifier("codeInterpreterArtifactStore") ArtifactStore<GeneratedFile> codeInterpreterArtifactStore,
@@-
@@+mcp-client The MCP client starter registers the Gateway tools under `mcpToolCallbacks`; Gateway web search replaces the local web grounding tool
        @Qualifier("mcpToolCallbacks") ToolCallbackProvider mcpTools,
@@-
@@+agent-as-tool Inject the compliance auditor tool
        ComplianceTools complianceTools,
@@-
@@+guardrails Inject the guardrail helper
        Guardrail guardrail,
@@-
@@+identity Inject the corporate calendar tool
        CalendarTools calendarTools,
@@-
@@+document-processing Inject the attachment handling
        Attachments attachments,
@@-
@@+policies Inject the Gateway tools of both Gateways
        GatewayTools gatewayTools,
@@-
@@+optimize Inject the system prompt advisor of the configuration bundle
        PromptConfig promptConfig,
@@-
@@+memory
        ChatClient.Builder chatClientBuilder) {

        List<Advisor> advisors = new ArrayList<>();

@@-
@@+optimize Take the system prompt from the configuration bundle when `CONFIG_BUNDLE_ID` is set; first, so that the other advisors add to it
        // System prompt from the configuration bundle
        if (promptConfig.enabled()) {
            advisors.add(promptConfig);
            logger.info("System prompt from the configuration bundle enabled");
        }

@@-
@@+memory `agentCoreMemory.advisors` holds the LTM advisors first, then STM; the starter sets the order
        // Memory (STM + LTM)
        advisors.addAll(agentCoreMemory.advisors);
        logger.info("Memory enabled: {} advisors", agentCoreMemory.advisors.size());
@@-
@@+knowledge The custom template treats the Knowledge Base as reference material, so the agent still answers questions the policies don't cover

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
@@-
@@+tools The context advisor adds date, time, and user to every prompt; the web grounding tool is a local tool

        // ContextAdvisor
        advisors.add(contextAdvisor);
        logger.info("Context Advisor enabled");
@@-
@@+tools The context advisor adds date, time, and user to every prompt; the web grounding tool is a local tool
@@!mcp-client

        // Tools
        List<Object> localTools = new ArrayList<>();
        localTools.add(webGroundingTools);
        logger.info("Web Grounding enabled");
@@-
@@+browser Keep the artifact store and links for `appendScreenshots()`; the browser tools go into the tool callback providers

        // Browser
        this.browserArtifactStore = browserArtifactStore;
        this.artifactLinks = artifactLinks;

        // Tool Callback Providers
        List<ToolCallbackProvider> toolCallbackProviders = new ArrayList<>();
@@-
@@+browser Keep the artifact store and links for `appendScreenshots()`; the browser tools go into the tool callback providers
@@!guardrails
        toolCallbackProviders.add(browserTools);
@@-
@@+guardrails Check the page text that `browseUrl` and `evaluateScript` return before the model reads it
        this.guardrail = guardrail;
        toolCallbackProviders.add(guardrail.guard(browserTools, "browseUrl", "evaluateScript"));
@@-
@@+browser
        logger.info("Browser enabled");
@@-
@@+code-interpreter Keep the artifact store for `appendGeneratedFiles()`; add the code interpreter tool

        // Code Interpreter
        this.codeInterpreterArtifactStore = codeInterpreterArtifactStore;
        toolCallbackProviders.add(codeInterpreterTools);
        logger.info("Code Interpreter enabled");
@@-
@@+mcp-client Add the Gateway tools to the tool callback providers

        // MCP Tools
@@-
@@+mcp-client Add the Gateway tools to the tool callback providers
@@!policies
        toolCallbackProviders.add(mcpTools);
@@-
@@+policies With the JWT Gateway, the backoffice tools come from there for each user; the IAM Gateway keeps the other tools
        this.gatewayTools = gatewayTools;
        toolCallbackProviders.add(gatewayTools.withoutBackoffice(mcpTools));
@@-
@@+mcp-client
        logger.info("MCP tools enabled");
@@-
@@+agent-as-tool Add the compliance auditor tool when `AUDITOR_HARNESS_ARN` is set

        // Compliance auditor (agent as tool)
        this.complianceTools = complianceTools;
        if (complianceTools.enabled()) {
            toolCallbackProviders.add(MethodToolCallbackProvider.builder().toolObjects(complianceTools).build());
            logger.info("Compliance auditor enabled");
        }
@@-
@@+identity Add the calendar tool when `CALENDAR_URL` is set

        // Corporate calendar (3LO)
        this.calendarTools = calendarTools;
        if (calendarTools.enabled()) {
            toolCallbackProviders.add(MethodToolCallbackProvider.builder().toolObjects(calendarTools).build());
            logger.info("Calendar enabled");
        }
@@-
@@+document-processing Keep the attachment handling for `chat()`

        // Attachments
        this.attachments = attachments;
@@-
@@+memory

@@-
        this.chatClient = chatClientBuilder
@@+persona `defaultSystem()` applies the system prompt to all requests
@@!browser
            .defaultSystem(SYSTEM_PROMPT)
@@-
@@+browser Tell the model where to find flight and hotel offers
            .defaultSystem(SYSTEM_PROMPT + "\nFlight and hotel offers: the corporate travel portal " + portalUrl + "\n")
@@-
@@+memory Register the advisors with the `ChatClient`
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
@@-
@@+tools Register the local tools
@@!mcp-client
            .defaultTools(localTools.toArray())
@@-
@@+browser `.defaultTools()` also accepts `ToolCallbackProvider` instances; the calls accumulate
            .defaultTools(toolCallbackProviders.toArray())
@@-
            .build();
    }

    @AgentCoreInvocation
@@!memory
    public Flux<String> chat(ChatRequest request) {
        return chatClient.prompt().user(request.prompt()).stream().content();
    }
@@-
@@+memory The conversation ID comes from the session header
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
@@-
@@+memory
@@!identity
        return chat(request.prompt(), getConversationId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
@@-
@@+identity The callback page sends the consent session back; the tools read the request headers from the Reactor context
        String sessionId = getConversationId(context);
        if (request.oauthSession() != null) {
            calendarTools.completeAuthorization(request.oauthSession(), sessionId, context);
            return Flux.just("The corporate calendar is connected. Send your question again.");
        }
        return chat(request, sessionId, context);
    }

    private Flux<String> chat(ChatRequest request, String sessionId, AgentCoreContext context) {
@@-
@@+memory
@@!guardrails
        return chatClient.prompt().user(prompt)
@@-
@@+guardrails Mask payment data before the memory advisors store the prompt
@@!identity
        return chatClient.prompt().user(guardrail.maskPii(prompt))
@@-
@@+identity
@@!document-processing
        return chatClient.prompt().user(guardrail.maskPii(request.prompt()))
@@-
@@+document-processing Add the attached file to the message
        String prompt = guardrail.maskPii(request.prompt());
        return chatClient.prompt().user(user -> attachments.message(user, prompt, request.fileName(), request.fileBase64()))
@@-
@@+policies Add the backoffice tools of the JWT Gateway for this user
            .toolCallbacks(gatewayTools.forUser(context))
@@-
@@+memory
@@!optimize
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
@@-
@@+optimize During an A/B test the request names the bundle version in its `baggage` header
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId).param(PromptConfig.BAGGAGE, PromptConfig.baggage(context)))
@@-
@@+memory
@@!browser
            .stream().content();
@@-
@@+browser Append screenshots after the answer; the session ID goes into the Reactor context for the tools
            .stream().content()
@@-
@@+code-interpreter Append generated files (charts, CSVs) after the answer
            .concatWith(Flux.defer(() -> appendGeneratedFiles(sessionId)))
@@-
@@+browser Append screenshots after the answer; the session ID goes into the Reactor context for the tools
            .concatWith(Flux.defer(() -> appendScreenshots(sessionId)))
@@-
@@+agent-as-tool Append the links to the audit reports after the answer
            .concatWith(Flux.defer(() -> appendAuditReports(sessionId)))
@@-
@@+browser Append screenshots after the answer; the session ID goes into the Reactor context for the tools
@@!identity
            .contextWrite(ctx -> ctx.put(SessionConstants.SESSION_ID_KEY, sessionId));
@@-
@@+identity
            .contextWrite(ctx -> ctx.put(SessionConstants.SESSION_ID_KEY, sessionId).put(CalendarTools.REQUEST_KEY, context));
@@-
@@+memory
    }

    private String getConversationId(AgentCoreContext context) {
@@-
@@+memory
@@!deploy
        return context.getHeader(AgentCoreHeaders.SESSION_ID);
@@-
@@+deploy The conversation ID combines the Cognito user ID from the JWT with the session ID
        return ConversationIdResolver.resolve(context);
@@-
@@+memory
    }
@@-
@@+browser Format screenshots as markdown images with presigned S3 links

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
@@-
@@+code-interpreter Images render inline, other files as download links; the sandbox's npm files are skipped

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
@@-
@@+agent-as-tool The auditor already uploaded the report; the links are presigned S3 URLs

    private Flux<String> appendAuditReports(String sessionId) {
        StringBuilder sb = new StringBuilder();
        for (String link : complianceTools.takeReportLinks(sessionId)) {
            sb.append("\n\n[Download audit-report.md](").append(link).append(")");
        }
        return sb.isEmpty() ? Flux.empty() : Flux.just(sb.toString());
    }
@@-
}
