package com.example.ai.agent.service;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.Message;
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

    private final MessageWindowChatMemory sessionMemory;
    private final MessageWindowChatMemory contextMemory;
    private final MessageWindowChatMemory preferencesMemory;

    // Thread-local to store current userId per request
    private final ThreadLocal<String> currentUserId = ThreadLocal.withInitial(() -> "user1");

    public ChatMemoryService(DataSource dataSource) {

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

        // Load user preferences (userId_preferences)
        List<Message> preferences = preferencesMemory.get(conversationId + "_preferences");
        String preferencesText = preferences.isEmpty() ? "" : preferences.get(0).getText();

        // Load context summaries (userId_context)
        List<Message> summaries = contextMemory.get(conversationId + "_context");

        if (summaries.isEmpty() && preferencesText.isEmpty()) {
            logger.info("No previous context found");
            return;
        }

        logger.info("Found {} context summaries and {} preferences", summaries.size(), preferences.isEmpty() ? 0 : 1);

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

        String contextSummary = (chatResponse != null && chatResponse.getResult() != null && chatResponse.getResult().getOutput() != null)
            ? chatResponse.getResult().getOutput().getText()
            : null;

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
