package com.example.ai.agent.service;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.InMemoryChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.context.annotation.Lazy;
import reactor.core.publisher.Flux;

import org.springframework.stereotype.Service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.sql.DataSource;
import java.util.List;

@Service
public class ChatMemoryService {
    private static final Logger logger = LoggerFactory.getLogger(ChatMemoryService.class);
    private static final int MAX_SESSION_MESSAGES = 30;
    private static final int MAX_SUMMARIES = 10;
    private static final int MAX_PREFERENCES = 1;

    private final MessageWindowChatMemory sessionMemory;
    private final MessageWindowChatMemory longTermMemory;
    private final MessageWindowChatMemory preferencesMemory;
    private final ChatService chatService;

    // Thread-local to store current userId per request
    private final ThreadLocal<String> currentUserId = ThreadLocal.withInitial(() -> "user1");

    public ChatMemoryService(DataSource dataSource, @Lazy ChatService chatService) {
        this.chatService = chatService;

        // InMemory for current session (last 30 messages)
        this.sessionMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(new InMemoryChatMemoryRepository())
            .maxMessages(MAX_SESSION_MESSAGES)
            .build();

        // JDBC for long-term summaries (last 10)
        var jdbcRepository = JdbcChatMemoryRepository.builder()
            .dataSource(dataSource)
            .dialect(new PostgresChatMemoryRepositoryDialect())
            .build();

        this.longTermMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(jdbcRepository)
            .maxMessages(MAX_SUMMARIES)
            .build();

        // JDBC for user preferences (single record)
        this.preferencesMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(jdbcRepository)
            .maxMessages(MAX_PREFERENCES)
            .build();

        logger.info("ChatMemoryService initialized with InMemory (max {} messages) + JDBC (max {} summaries + {} preferences)",
            MAX_SESSION_MESSAGES, MAX_SUMMARIES, MAX_PREFERENCES);
    }

    public MessageWindowChatMemory getSessionMemory() {
        return sessionMemory;
    }

    public MessageWindowChatMemory getLongTermMemory() {
        return longTermMemory;
    }

    public MessageWindowChatMemory getPreferencesMemory() {
        return preferencesMemory;
    }

    public void setCurrentUserId(String userId) {
        this.currentUserId.set(userId);
    }

    public String getCurrentConversationId() {
        return currentUserId.get();
    }

    public Flux<String> callWithMemory(ChatClient chatClient, String prompt) {
        String conversationId = getCurrentConversationId();

        // Check if first message - load previous context from JDBC
        if (sessionMemory.get(conversationId).isEmpty()) {
            loadPreviousContext(conversationId, chatClient);
        }

        // Add user message to session memory
        UserMessage userMessage = new UserMessage(prompt);
        sessionMemory.add(conversationId, userMessage);

        // Stream response with conversation history
        StringBuilder fullResponse = new StringBuilder();

        return chatClient
                .prompt(new Prompt(sessionMemory.get(conversationId)))
                .stream()
                .content()
                .doOnNext(chunk -> {
                    fullResponse.append(chunk);
                    logger.debug("Streaming chunk: {} chars", chunk.length());
                })
                .doOnComplete(() -> {
                    // Add complete assistant response to session memory after streaming completes
                    String responseText = fullResponse.toString();
                    if (responseText != null && !responseText.isEmpty()) {
                        AssistantMessage assistantMessage = new AssistantMessage(responseText);
                        sessionMemory.add(conversationId, assistantMessage);
                        logger.info("Added assistant response to memory: {} chars", responseText.length());
                    }
                    logger.info("Completed streaming response.");
                });
    }

    private void loadPreviousContext(String conversationId, ChatClient chatClient) {
        logger.info("Loading previous context for conversation: {}", conversationId);

        // Load user preferences
        List<Message> preferences = preferencesMemory.get(conversationId + "_preferences");
        String preferencesText = preferences.isEmpty() ? "" : preferences.get(0).getText();

        // Load conversation summaries
        List<Message> summaries = longTermMemory.get(conversationId);

        if (summaries.isEmpty() && preferencesText.isEmpty()) {
            logger.info("No previous context found");
            return;
        }

        logger.info("Found {} previous summaries and {} preferences", summaries.size(), preferences.isEmpty() ? 0 : 1);

        // Combine preferences and summaries
        StringBuilder contextBuilder = new StringBuilder();
        if (!preferencesText.isEmpty()) {
            contextBuilder.append("User Preferences:\n").append(preferencesText).append("\n\n");
        }
        if (!summaries.isEmpty()) {
            contextBuilder.append("Previous Conversations:\n");
            summaries.forEach(msg -> contextBuilder.append(msg.getText()).append("\n\n"));
        }

        String combinedContext = contextBuilder.toString();
        var chatResponse = chatClient.prompt()
            .user("Summarize this user information concisely:\n\n" + combinedContext)
            .call()
            .chatResponse();

        String contextSummary = chatService.extractTextFromResponse(chatResponse);

        if (contextSummary == null || contextSummary.isEmpty()) {
            logger.warn("Failed to generate context summary");
            return;
        }

        logger.info("Loaded context summary: {}", contextSummary);

        String contextMessage = String.format(
            "You are continuing a conversation with this user. Here is what you know:\n\n%s\n\n" +
            "Use this information to provide personalized responses.",
            contextSummary
        );
        sessionMemory.add(conversationId, new SystemMessage(contextMessage));
    }
}
