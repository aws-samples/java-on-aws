package com.example.ai.agent.service;

import com.example.ai.agent.model.ChatRequest;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.context.annotation.Lazy;

import org.springframework.stereotype.Service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.sql.DataSource;

@Service
public class ChatMemoryService {
    private static final Logger logger = LoggerFactory.getLogger(ChatMemoryService.class);
    public static final String DEFAULT_CONVERSATION_ID = "user1";

    private final MessageWindowChatMemory chatMemory;
    private final ChatService chatService;

    public ChatMemoryService(DataSource dataSource, @Lazy ChatService chatService) {
        this.chatService = chatService;
        var chatMemoryRepository = JdbcChatMemoryRepository.builder()
            .dataSource(dataSource)
            .dialect(new PostgresChatMemoryRepositoryDialect())
            .build();

        this.chatMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(chatMemoryRepository)
            .maxMessages(50)
            .build();

        logger.info("ChatMemoryService initialized with JDBC repository");
    }

    public MessageWindowChatMemory getChatMemory() {
        return chatMemory;
    }

    public String getCurrentConversationId() {
        return DEFAULT_CONVERSATION_ID; // In a real app, this would come from auth context
    }

    public org.springframework.ai.chat.model.ChatResponse callWithMemory(ChatClient chatClient, ChatRequest request) {
        String conversationId = getCurrentConversationId();

        // Add user message to memory
        UserMessage userMessage = new UserMessage(request.prompt());
        chatMemory.add(conversationId, userMessage);

        // Make call with conversation history
        var chatResponse = chatClient
                .prompt(new Prompt(chatMemory.get(conversationId)))
                .call()
                .chatResponse();

        // Add assistant response to memory if we can extract content
        if (chatResponse != null && chatResponse.getResult() != null && chatResponse.getResult().getOutput() != null) {
            String responseText = chatService.extractTextFromResponse(chatResponse);
            if (responseText != null && !responseText.isEmpty()) {
                AssistantMessage assistantMessage = new AssistantMessage(responseText);
                chatMemory.add(conversationId, assistantMessage);
            }
        }

        return chatResponse;
    }
}
