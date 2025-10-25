package com.example.ai.agent;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;

import org.springframework.stereotype.Service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.sql.DataSource;

@Service
public class ChatMemoryService {
    private static final Logger logger = LoggerFactory.getLogger(ChatMemoryService.class);

    private final MessageWindowChatMemory chatMemory;

    public ChatMemoryService(DataSource dataSource) {
        var chatMemoryRepository = JdbcChatMemoryRepository.builder()
            .dataSource(dataSource)
            .dialect(new PostgresChatMemoryRepositoryDialect())
            .build();

        this.chatMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(chatMemoryRepository)
            .maxMessages(20)
            .build();

        logger.info("ChatMemoryService initialized with JDBC repository");
    }

    public MessageWindowChatMemory getChatMemory() {
        return chatMemory;
    }

    public String getCurrentConversationId() {
        return "user1"; // In a real app, this would come from auth context
    }

    public void addConversationIdToAdvisor(ChatClient.AdvisorSpec advisor) {
        String conversationId = getCurrentConversationId();
        logger.debug("Adding conversation ID {} to advisor", conversationId);
        advisor.param(ChatMemory.CONVERSATION_ID, conversationId);
    }
}
