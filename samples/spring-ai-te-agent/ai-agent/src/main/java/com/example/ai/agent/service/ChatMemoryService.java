package com.example.ai.agent.service;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import org.springframework.ai.chat.messages.*;
import org.springframework.ai.chat.prompt.Prompt;
import reactor.core.publisher.Flux;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.sql.DataSource;
import java.util.List;

@Service
public class ChatMemoryService {
    private static final Logger logger = LoggerFactory.getLogger(ChatMemoryService.class);
    private static final int MAX_SESSION_MESSAGES = 20;
    private static final int MAX_CONTEXT_SUMMARIES = 10;
    private static final int MAX_PREFERENCES = 1;

    // Three-tier memory: Session (recent), Context (summaries), Preferences (profile)
    private final MessageWindowChatMemory sessionMemory;
    private final MessageWindowChatMemory contextMemory;
    private final MessageWindowChatMemory preferencesMemory;
    private final ThreadLocal<String> currentUserId = ThreadLocal.withInitial(() -> "user1");

    public ChatMemoryService(DataSource dataSource) {
        // Single JDBC repository shared by all three memory tiers
        var jdbcRepository = JdbcChatMemoryRepository.builder()
            .dataSource(dataSource)
            .dialect(new PostgresChatMemoryRepositoryDialect())
            .build();

        this.sessionMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(jdbcRepository)
            .maxMessages(MAX_SESSION_MESSAGES)
            .build();

        this.contextMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(jdbcRepository)
            .maxMessages(MAX_CONTEXT_SUMMARIES)
            .build();

        this.preferencesMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(jdbcRepository)
            .maxMessages(MAX_PREFERENCES)
            .build();
    }

    public Flux<String> callWithMemory(ChatClient chatClient, String prompt) {
        String conversationId = getCurrentConversationId();

        // 1. Auto-load previous context on first message
        if (sessionMemory.get(conversationId).isEmpty()) {
            loadPreviousContext(conversationId, chatClient);
        }

        // 2. Add user message to session memory
        sessionMemory.add(conversationId, new UserMessage(prompt));

        // 3. Stream AI response with full conversation history
        StringBuilder fullResponse = new StringBuilder();
        return chatClient
                .prompt(new Prompt(sessionMemory.get(conversationId)))
                .stream()
                .content()
                .doOnNext(fullResponse::append)
                .doOnComplete(() -> {
                    // 4. Save complete response to session memory
                    String responseText = fullResponse.toString();
                    if (!responseText.isEmpty()) {
                        sessionMemory.add(conversationId, new AssistantMessage(responseText));
                        logger.info("Saved response to memory: {} chars", responseText.length());
                    }
                });
    }

    private void loadPreviousContext(String conversationId, ChatClient chatClient) {
        logger.info("Loading previous context for: {}", conversationId);

        // 1. Load preferences (userId_preferences) and context (userId_context)
        List<Message> preferences = preferencesMemory.get(conversationId + "_preferences");
        String preferencesText = preferences.isEmpty() ? "" : preferences.get(0).getText();
        List<Message> summaries = contextMemory.get(conversationId + "_context");

        if (summaries.isEmpty() && preferencesText.isEmpty()) {
            logger.info("No previous context found");
            return;
        }

        logger.info("Found {} summaries, {} preferences", summaries.size(), preferences.isEmpty() ? 0 : 1);

        // 2. Combine preferences and summaries
        StringBuilder contextBuilder = new StringBuilder();
        if (!preferencesText.isEmpty()) {
            contextBuilder.append("User Preferences:\n").append(preferencesText).append("\n\n");
        }
        if (!summaries.isEmpty()) {
            contextBuilder.append("Previous Conversations:\n");
            summaries.forEach(msg -> contextBuilder.append(msg.getText()).append("\n\n"));
        }

        // 3. Summarize combined context with AI
        var chatResponse = chatClient.prompt()
            .user("Summarize this user information concisely:\n\n" + contextBuilder)
            .call()
            .chatResponse();

        String contextSummary = (chatResponse != null &&
            chatResponse.getResult() != null &&
            chatResponse.getResult().getOutput() != null)
            ? chatResponse.getResult().getOutput().getText()
            : null;

        if (contextSummary == null || contextSummary.isEmpty()) {
            logger.warn("Failed to generate context summary");
            return;
        }

        // 4. Add context as system message to session memory
        String contextMessage = String.format(
            "You are continuing a conversation with this user. Here is what you know:\n\n%s\n\n" +
            "Use this information to provide personalized responses.",
            contextSummary
        );
        sessionMemory.add(conversationId, new SystemMessage(contextMessage));
        logger.info("Loaded context summary");
    }

    // Getters and setters
    public MessageWindowChatMemory getSessionMemory() {
        return sessionMemory;
    }

    public MessageWindowChatMemory getContextMemory() {
        return contextMemory;
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
}
