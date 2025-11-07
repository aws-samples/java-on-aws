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
    private final ChatClient chatClient;

    public ConversationSummaryService(ChatMemoryService chatMemoryService,
                                     ChatClient.Builder chatClientBuilder) {
        this.chatMemoryService = chatMemoryService;
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

        // Get existing preferences for merging
        List<Message> existingPrefs = chatMemoryService.getPreferencesMemory().get(conversationId + "_preferences");
        String existingPrefsText = existingPrefs.isEmpty() ? "" : existingPrefs.get(0).getText();

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

        String preferencesPrompt = existingPrefsText.isEmpty()
            ? "Extract static user information (name, email, preferences). If none, return empty."
            : "Merge preferences. Keep existing:\n" + existingPrefsText +
              "\nAdd new from conversation. Update only if explicitly changed. Never remove existing.";

        var chatResponse = chatClient.prompt()
            .user("Analyze this conversation and provide TWO separate summaries:\n\n" +
                  "PREFERENCES:\n" +
                  preferencesPrompt + "\n\n" +
                  "CONTEXT:\n" +
                  "Summarize conversation context:\n" +
                  "- Topics discussed\n" +
                  "- Questions asked\n" +
                  "- Decisions or actions taken\n" +
                  "- Pending items or follow-ups\n\n" +
                  "DO NOT include: prices, dates, flight numbers, hotel names, company policies.\n\n" +
                  "Output format (plain text, no JSON):\n" +
                  "===PREFERENCES===\n" +
                  "[preferences here]\n" +
                  "===CONTEXT===\n" +
                  "[context here]\n\n" +
                  "Conversation:\n" + messagesText)
            .call()
            .chatResponse();

        String response = (chatResponse != null && chatResponse.getResult() != null && chatResponse.getResult().getOutput() != null)
            ? chatResponse.getResult().getOutput().getText()
            : null;

        if (response == null || response.trim().isEmpty()) {
            logger.error("Generated summary is null or empty");
            throw new RuntimeException("Failed to generate summary");
        }

        // Parse plain text response
        String preferences = "";
        String context = "";
        try {
            if (response.contains("===PREFERENCES===")) {
                int prefStart = response.indexOf("===PREFERENCES===") + 17;
                int prefEnd = response.indexOf("===CONTEXT===");
                if (prefEnd > prefStart) {
                    preferences = response.substring(prefStart, prefEnd).trim();
                }
            }
            if (response.contains("===CONTEXT===")) {
                int ctxStart = response.indexOf("===CONTEXT===") + 13;
                context = response.substring(ctxStart).trim();
            }
        } catch (Exception e) {
            logger.warn("Failed to parse response, using full response as context", e);
            context = response;
        }

        logger.info("Generated preferences: {}", preferences);
        logger.info("Generated context: {}", context);

        // Save preferences (only if not empty)
        if (!preferences.isEmpty()) {
            chatMemoryService.getPreferencesMemory().add(conversationId + "_preferences", new AssistantMessage(preferences));
            logger.info("Saved preferences to memory");
        }

        // Save context to JDBC (userId_context)
        if (!context.isEmpty()) {
            String timestamp = java.time.LocalDateTime.now()
                .format(java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd HHmmss"));
            String contextWithTimestamp = "[" + timestamp + "] " + context;
            chatMemoryService.getContextMemory().add(conversationId + "_context", new AssistantMessage(contextWithTimestamp));
            logger.info("Saved context to memory with timestamp");
        }

        // Clear session memory
        chatMemoryService.getSessionMemory().clear(conversationId);

        logger.info("Summary saved, session cleared");

        String timestamp = java.time.LocalDateTime.now()
            .format(java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd HHmmss"));

        return "**Summary:** [" + timestamp + "]\n\n" +
               "**Preferences:**\n" + (preferences.isEmpty() ? "None" : preferences) +
               "\n\n**Context:**\n" + context;
    }
}
