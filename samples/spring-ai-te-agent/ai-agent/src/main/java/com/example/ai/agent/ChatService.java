package com.example.ai.agent;

import io.github.resilience4j.retry.Retry;
import org.jetbrains.annotations.Nullable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.bedrockruntime.model.ValidationException;

@Service
public class ChatService {
    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;
    private final ChatMemoryService chatMemoryService;
    private final Retry chatRetry;

    public ChatService(ChatClient.Builder chatClientBuilder,
                      ChatMemoryService chatMemoryService,
                      VectorStore vectorStore,
                      DateTimeService dateTimeService,
                      ToolCallbackProvider tools,
                      Retry chatRetry) {
        this.chatClient = chatClientBuilder
                .defaultSystem(PromptConfig.SYSTEM_PROMPT)
                .defaultAdvisors(
                        // MessageChatMemoryAdvisor.builder(chatMemoryService.getChatMemory()).build(),
                        QuestionAnswerAdvisor.builder(vectorStore).build()  // Temporarily disabled
                )
                .defaultTools(dateTimeService)
                .defaultToolCallbacks(tools)
                .build();

        this.chatMemoryService = chatMemoryService;
        this.chatRetry = chatRetry;
        logger.info("ChatService initialized with embedded ChatClient");
    }

    public String processChat(ChatRequest request) {
        logger.info("Processing chat request - hasFile: {}, hasPrompt: {}, fileName: {}",
                request.hasFile(), request.hasPrompt(), request.fileName());
        try {
            if (!request.hasFile()) {
                return chatRetry.executeSupplier(() -> sendTextPrompt(request));
            } else {
                return chatRetry.executeSupplier(() -> sendFilePrompt(request));
            }
        } catch (Exception e) {
            return handleException(e);
        }
    }

    @Nullable
    private String sendTextPrompt(ChatRequest request) {
        logger.info("Input prompt: '{}'", request.prompt());
        var chatResponse = chatClient
                .prompt().user(request.prompt())
                .advisors(chatMemoryService::addConversationIdToAdvisor)
                .call()
                .chatResponse();

        return extractTextFromResponse(chatResponse);
    }

    @Nullable
    private String sendFilePrompt(ChatRequest request) {
        ChatRequest.FileResource fileResource = request.buildFileResource();
        String actualPrompt = request.getEffectivePrompt();

        logger.info("Using prompt for file {}: '{}'", request.fileName(), actualPrompt);

        var chatResponse = chatClient
                .prompt()
                .user(userSpec -> {
                    userSpec.text(actualPrompt);
                    userSpec.media(fileResource.mimeType(), fileResource.resource());
                })
                .advisors(chatMemoryService::addConversationIdToAdvisor)
                .call().chatResponse();

        return extractTextFromResponse(chatResponse);
    }

    private String extractTextFromResponse(org.springframework.ai.chat.model.ChatResponse chatResponse) {
        if (chatResponse != null) {
            // First try the standard approach
            String text = chatResponse.getResult().getOutput().getText();
            if (text != null && !text.isEmpty()) {
                return text;
            }

            // Fallback: iterate through generations for models with reasoning content
            if (!chatResponse.getResults().isEmpty()) {
                for (var generation : chatResponse.getResults()) {
                    String textContent = generation.getOutput().getText();
                    if (textContent != null && !textContent.isEmpty()) {
                        logger.info("Found text content: '{}'", textContent);
                        return textContent;
                    }
                }
            }
        }

        return "I don't know - no response received.";
    }

    private String handleException(Throwable throwable) {
        if (throwable instanceof ValidationException) {
            logger.warn("AWS Bedrock validation error: {}", throwable.getMessage());
            return "Invalid request format. Please check your input and try again.";
        } else if (ChatRetryConfig.isAwsThrottlingRelated(throwable)) {
            logger.error("Throttling exception after all retry attempts: {}", throwable.getMessage());
            return "The AI service is currently experiencing high demand. Please try again in a few minutes.";
        } else {
            logger.error("Error processing chat request", throwable);
            return "I don't know - there was an error processing your request.";
        }
    }
}
