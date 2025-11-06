package com.example.ai.agent.service;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.List;

@Service
public class ConversationSummaryService {
    private static final Logger logger = LoggerFactory.getLogger(ConversationSummaryService.class);

    private final ChatMemoryService chatMemoryService;
    private final ChatService chatService;
    private final ChatClient chatClient;

    public ConversationSummaryService(ChatMemoryService chatMemoryService,
                                     ChatService chatService,
                                     ChatClient.Builder chatClientBuilder) {
        this.chatMemoryService = chatMemoryService;
        this.chatService = chatService;
        this.chatClient = chatClientBuilder.build();
    }

    public String summarizeAndSave(String conversationId) {
        logger.info("Summarizing conversation: {}", conversationId);

        // Get current session messages
        List<Message> messages = chatMemoryService.getSessionMemory().get(conversationId);

        if (messages.isEmpty()) {
            logger.warn("No messages to summarize");
            return "No conversation to summarize";
        }

        // Create summary with AI
        String messagesText = messages.stream()
            .filter(msg -> msg.getText() != null && !msg.getText().isEmpty())
            .map(msg -> msg.getMessageType() + ": " + msg.getText())
            .reduce((a, b) -> a + "\n" + b)
            .orElse("");

        if (messagesText.isEmpty()) {
            logger.warn("No valid message content to summarize");
            return "No valid conversation content to summarize";
        }

        logger.info("Summarizing {} characters of conversation", messagesText.length());

        var chatResponse = chatClient.prompt()
            .user("Summarize this conversation, extracting key points, decisions, and user preferences:\n\n" + messagesText)
            .call()
            .chatResponse();

        String summary = chatService.extractTextFromResponse(chatResponse);

        if (summary == null || summary.trim().isEmpty()) {
            logger.error("Generated summary is null or empty");
            throw new RuntimeException("Failed to generate summary");
        }

        logger.info("Generated summary: {}", summary);

        // Save summary to long-term JDBC
        chatMemoryService.getLongTermMemory().add(conversationId, new AssistantMessage(summary));

        // Clear session memory
        chatMemoryService.getSessionMemory().clear(conversationId);

        // Reload summary into session memory as context
        chatMemoryService.getSessionMemory().add(conversationId,
            new SystemMessage("Summary of previous conversation: " + summary));

        logger.info("Summary saved to long-term memory and reloaded to session");

        return summary;
    }
}
