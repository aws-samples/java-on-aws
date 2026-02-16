package com.example.agent;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springaicommunity.agentcore.browser.BrowserScreenshot;
import org.springaicommunity.agentcore.browser.BrowserScreenshotStore;
import org.springaicommunity.agentcore.browser.BrowserTools;
import org.springaicommunity.agentcore.codeinterpreter.CodeInterpreterFileStore;
import org.springaicommunity.agentcore.codeinterpreter.CodeInterpreterTools;
import org.springaicommunity.agentcore.codeinterpreter.GeneratedFile;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.ChatMemoryRepository;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.model.tool.ToolCallingChatOptions;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.MediaTypeFactory;
import org.springframework.util.MimeType;
import org.springframework.util.MimeTypeUtils;
import java.util.Base64;

record ChatRequest(String prompt, String fileBase64, String fileName) {
    public boolean hasFile() {
        return fileBase64 != null && !fileBase64.isEmpty() && fileName != null && !fileName.isEmpty();
    }
}

@Service
public class ChatService {

    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;

    private final ChatClient documentClient;
    private final String documentModel;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    private final BrowserScreenshotStore screenshotStore;
    private final CodeInterpreterFileStore fileStore;

    private static final String SYSTEM_PROMPT = """
        You are a helpful AI agent for travel and expense management.
        Be friendly, helpful, and concise in your responses.
        """;

    public ChatService(@Autowired(required = false) ChatMemoryRepository memoryRepository,
        @Autowired(required = false) List<Advisor> ltmAdvisors,
        @Autowired(required = false) VectorStore kbVectorStore,
        @Autowired(required = false) WebGroundingTools webGroundingTools,
        ContextAdvisor contextAdvisor,
        @Autowired(required = false) @Qualifier("browserToolCallbackProvider") ToolCallbackProvider browserTools,
        @Autowired(required = false) BrowserScreenshotStore browserScreenshotStore,
        @Autowired(required = false) @Qualifier("codeInterpreterToolCallbackProvider") ToolCallbackProvider codeInterpreterTools,
        @Autowired(required = false) CodeInterpreterFileStore codeInterpreterFileStore,
        @Autowired(required = false) @Qualifier("mcpToolCallbacks") ToolCallbackProvider mcpTools,
        ChatModel chatModel,
        @Value("${app.ai.document.model:global.anthropic.claude-opus-4-5-20251101-v1:0}") String documentModel,
        ChatClient.Builder chatClientBuilder) {

        List<Advisor> advisors = new ArrayList<>();

        // Short-Term Memory (STM)
        if (memoryRepository != null) {
            ChatMemory chatMemory = MessageWindowChatMemory.builder()
                .chatMemoryRepository(memoryRepository)
                .build();
            advisors.add(MessageChatMemoryAdvisor.builder(chatMemory).build());
            logger.info("Memory enabled");
        }

        // Long-Term Memory (LTM)
        if (ltmAdvisors != null && !ltmAdvisors.isEmpty()) {
            advisors.addAll(ltmAdvisors);
            logger.info("Advisors enabled: {} advisors", ltmAdvisors.size());
        }

        // Knowledge Base (RAG)
        if (kbVectorStore != null) {
            advisors.add(QuestionAnswerAdvisor.builder(kbVectorStore).build());
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
        this.screenshotStore = browserScreenshotStore;

        // Tool Callback Providers
        List<ToolCallbackProvider> toolCallbackProviders = new ArrayList<>();
        if (browserTools != null) {
            toolCallbackProviders.add(browserTools);
            logger.info("Browser enabled");
        }

        // Code Interpreter
        this.fileStore = codeInterpreterFileStore;

        if (codeInterpreterTools != null) {
            toolCallbackProviders.add(codeInterpreterTools);
            logger.info("Code Interpreter enabled");
        }

        // MCP Tools
        if (mcpTools != null) {
            toolCallbackProviders.add(mcpTools);
            logger.info("MCP tools enabled");
        }

        this.documentModel = documentModel;
        this.documentClient = ChatClient.builder(chatModel).build();

        this.chatClient = chatClientBuilder.defaultSystem(SYSTEM_PROMPT)
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            .defaultTools(localTools.toArray())
            .defaultToolCallbacks(toolCallbackProviders.toArray(new ToolCallbackProvider[0]))
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
        if (request.hasFile()) {
            return processDocument(request.prompt(), request.fileBase64(), request.fileName())
                .collectList()
                .map(chunks -> String.join("", chunks))
                .flatMapMany(documentAnalysis -> {
                    String userPrompt = (request.prompt() != null && !request.prompt().trim().isEmpty())
                        ? request.prompt() : "Process this document";
                    String combinedPrompt = userPrompt + "\n\nDocument analysis:\n" + documentAnalysis;
                    return chat(combinedPrompt, getSessionId(context));
                });
        }
        return chat(request.prompt(), getSessionId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
        return chatClient.prompt().user(prompt)
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            .stream().content()
            .concatWith(Flux.defer(() -> appendGeneratedFiles(sessionId)))
            .concatWith(Flux.defer(() -> appendScreenshots(sessionId)))
            .contextWrite(ctx -> ctx.put(CodeInterpreterTools.SESSION_ID_CONTEXT_KEY, sessionId))
            .contextWrite(ctx -> ctx.put(BrowserTools.SESSION_ID_CONTEXT_KEY, sessionId));
    }

    private String getSessionId(AgentCoreContext context) {
        String authHeader = context.getHeader(AgentCoreHeaders.AUTHORIZATION);
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            String jwt = authHeader.replace("Bearer ", "");
            String payload = new String(Base64.getUrlDecoder().decode(jwt.split("\\.")[1]));
            JsonNode claims = jsonMapper.readTree(payload);
            String sub = claims.get("sub").asString().replace("-", "").substring(0, 25);
            return sub + ":" + claims.get("auth_time").asString();
        }
        return (authHeader != null && !authHeader.isBlank()) ? authHeader : "default-user";
    }

    private Flux<String> appendScreenshots(String sessionId) {
        if (screenshotStore == null) {
            return Flux.empty();
        }
        List<BrowserScreenshot> screenshots = screenshotStore.retrieve(sessionId);
        if (screenshots == null || screenshots.isEmpty()) {
            return Flux.empty();
        }
        return Flux.just(formatScreenshotsAsMarkdown(screenshots));
    }

    private String formatScreenshotsAsMarkdown(List<BrowserScreenshot> screenshots) {
        StringBuilder sb = new StringBuilder();
        for (BrowserScreenshot screenshot : screenshots) {
            sb.append("\n\n![Screenshot of ")
                .append(screenshot.url())
                .append("](")
                .append(screenshot.toDataUrl())
                .append(")");
        }
        return sb.toString();
    }

    private Flux<String> appendGeneratedFiles(String sessionId) {
        if (fileStore == null) {
            return Flux.empty();
        }
        List<GeneratedFile> files = fileStore.retrieve(sessionId);
        if (files == null || files.isEmpty()) {
            return Flux.empty();
        }
        return Flux.just(formatFilesAsMarkdown(files));
    }

    private String formatFilesAsMarkdown(List<GeneratedFile> files) {
        StringBuilder sb = new StringBuilder();
        for (GeneratedFile file : files) {
            if (file.isImage()) {
                sb.append("\n\n![").append(file.name()).append("](")
                    .append(file.toDataUrl()).append(")");
            } else {
                sb.append("\n\n[Download ").append(file.name()).append("](")
                    .append(file.toDataUrl()).append(")");
            }
        }
        return sb.toString();
    }

    private Flux<String> processDocument(String prompt, String fileBase64, String fileName) {
        logger.info("Processing document: {}", fileName);

        MimeType mimeType = determineMimeType(fileName);
        byte[] fileData = Base64.getDecoder().decode(fileBase64);
        ByteArrayResource resource = new ByteArrayResource(fileData);
        String userPrompt = (prompt != null && !prompt.trim().isEmpty()) ? prompt : "Analyze this document";

        return documentClient.prompt()
            .options(ToolCallingChatOptions.builder().model(documentModel).build())
            .user(userSpec -> {
                userSpec.text(userPrompt);
                userSpec.media(mimeType, resource);
            })
            .stream()
            .content()
            .onErrorResume(error -> {
                logger.error("Error processing document", error);
                return Flux.just("Error analyzing document: " + error.getMessage());
            });
    }

    private MimeType determineMimeType(String fileName) {
        if (fileName != null && !fileName.trim().isEmpty()) {
            MediaType mediaType = MediaTypeFactory.getMediaType(fileName).orElse(MediaType.APPLICATION_OCTET_STREAM);
            return new MimeType(mediaType.getType(), mediaType.getSubtype());
        }
        return MimeTypeUtils.APPLICATION_OCTET_STREAM;
    }
}