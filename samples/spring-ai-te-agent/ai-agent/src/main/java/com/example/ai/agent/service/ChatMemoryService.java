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

    private final MessageWindowChatMemory sessionMemory;
    private final MessageWindowChatMemory longTermMemory;
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

        logger.info("ChatMemoryService initialized with InMemory (max {} messages) + JDBC (max {} summaries)",
            MAX_SESSION_MESSAGES, MAX_SUMMARIES);
    }

    public MessageWindowChatMemory getSessionMemory() {
        return sessionMemory;
    }

    public MessageWindowChatMemory getLongTermMemory() {
        return longTermMemory;
    }

    public void setCurrentUserId(String userId) {
        this.currentUserId.set(userId);
    }

    public String getCurrentConversationId() {
        return currentUserId.get();
    }

    public org.springframework.ai.chat.model.ChatResponse callWithMemory(ChatClient chatClient, String prompt) {
        String conversationId = getCurrentConversationId();

        // Check if first message - load previous context from JDBC
        if (sessionMemory.get(conversationId).isEmpty()) {
            loadPreviousContext(conversationId, chatClient);
        }

        // Add user message to session memory
        UserMessage userMessage = new UserMessage(prompt);
        sessionMemory.add(conversationId, userMessage);

        // Make call with conversation history from session memory
        var chatResponse = chatClient
                .prompt(new Prompt(sessionMemory.get(conversationId)))
                .call()
                .chatResponse();

        // Add assistant response to session memory
        if (chatResponse != null && chatResponse.getResult() != null && chatResponse.getResult().getOutput() != null) {
            String responseText = chatService.extractTextFromResponse(chatResponse);
            if (responseText != null && !responseText.isEmpty()) {
                AssistantMessage assistantMessage = new AssistantMessage(responseText);
                sessionMemory.add(conversationId, assistantMessage);
            }
        }

        return chatResponse;
    }

    private void loadPreviousContext(String conversationId, ChatClient chatClient) {
        logger.info("Loading previous context for conversation: {}", conversationId);

        // Get summaries from JDBC
        List<Message> summaries = longTermMemory.get(conversationId);

        if (summaries.isEmpty()) {
            logger.info("No previous context found");
            return;
        }

        logger.info("Found {} previous summaries", summaries.size());

        // Summarize the summaries with AI
        String summariesText = summaries.stream()
            .map(Message::getText)
            .reduce((a, b) -> a + "\n" + b)
            .orElse("");

        var chatResponse = chatClient.prompt()
            .user("Summarize these previous conversation summaries concisely: " + summariesText)
            .call()
            .chatResponse();

        String contextSummary = chatService.extractTextFromResponse(chatResponse);

        if (contextSummary == null || contextSummary.isEmpty()) {
            logger.warn("Failed to generate context summary");
            return;
        }

        logger.info("Loaded context summary: {}", contextSummary);

        // Add to session memory as system message with clear instruction
        String contextMessage = String.format(
            "You are continuing a conversation with this user. Here is what you know from previous sessions:\n\n%s\n\n" +
            "Use this information to provide personalized responses. If the user asks about themselves, refer to this context.",
            contextSummary
        );
        sessionMemory.add(conversationId, new SystemMessage(contextMessage));
    }
}
