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
            ? "Extract ONLY static user information (name, email, preferences, dietary restrictions). If none found, return empty string."
            : "MERGE preferences - keep ALL existing information and ADD any new information:\n\n" +
              "EXISTING PREFERENCES (keep everything):\n" + existingPrefsText + "\n\n" +
              "INSTRUCTIONS:\n" +
              "1. Start with ALL existing preferences above\n" +
              "2. Add any NEW preferences from the conversation\n" +
              "3. Update ONLY if explicitly changed by user\n" +
              "4. Never remove existing information\n" +
              "Output the complete merged preferences.";

        var chatResponse = chatClient.prompt()
            .user("Analyze this conversation and provide TWO separate summaries:\n\n" +
                  "## PREFERENCES (output as JSON with key 'preferences'):\n" +
                  preferencesPrompt + "\n\n" +
                  "## CONTEXT (output as JSON with key 'context'):\n" +
                  "Summarize conversation context:\n" +
                  "- Topics discussed\n" +
                  "- Questions asked\n" +
                  "- Decisions or actions taken\n" +
                  "- Pending items or follow-ups\n\n" +
                  "DO NOT include: prices, dates, flight numbers, hotel names, company policies.\n\n" +
                  "Output format: {\"preferences\": \"...\", \"context\": \"...\"}\n\n" +
                  "Conversation:\n" + messagesText)
            .call()
            .chatResponse();

        String response = chatService.extractTextFromResponse(chatResponse);

        if (response == null || response.trim().isEmpty()) {
            logger.error("Generated summary is null or empty");
            throw new RuntimeException("Failed to generate summary");
        }

        // Parse JSON response
        String preferences = "";
        String context = "";
        try {
            // Simple JSON parsing (or use Jackson if available)
            if (response.contains("\"preferences\"")) {
                int prefStart = response.indexOf("\"preferences\"") + 15;
                int prefEnd = response.indexOf("\",", prefStart);
                if (prefEnd == -1) prefEnd = response.indexOf("\"}", prefStart);
                preferences = response.substring(prefStart, prefEnd).trim();
            }
            if (response.contains("\"context\"")) {
                int ctxStart = response.indexOf("\"context\"") + 11;
                int ctxEnd = response.lastIndexOf("\"");
                context = response.substring(ctxStart, ctxEnd).trim();
            }
        } catch (Exception e) {
            logger.warn("Failed to parse JSON, using full response as context", e);
            context = response;
        }

        logger.info("Generated preferences: {}", preferences);
        logger.info("Generated context: {}", context);

        // Save preferences (only if not empty)
        if (!preferences.isEmpty()) {
            chatMemoryService.getPreferencesMemory().add(conversationId + "_preferences", new AssistantMessage(preferences));
            logger.info("Saved preferences to memory");
        }

        // Save context to long-term JDBC
        if (!context.isEmpty()) {
            chatMemoryService.getLongTermMemory().add(conversationId, new AssistantMessage(context));
            logger.info("Saved context to long-term memory");
        }

        // Clear session memory
        chatMemoryService.getSessionMemory().clear(conversationId);

        // Reload into session memory as context
        if (!preferences.isEmpty()) {
            chatMemoryService.getSessionMemory().add(conversationId,
                new SystemMessage("User preferences: " + preferences));
        }
        if (!context.isEmpty()) {
            chatMemoryService.getSessionMemory().add(conversationId,
                new SystemMessage("Previous conversation: " + context));
        }

        logger.info("Summary saved and reloaded to session");

        return "Preferences: " + (preferences.isEmpty() ? "None" : preferences) + "\n\nContext: " + context;
    }
}
