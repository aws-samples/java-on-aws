package com.example.ai.agent.service;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

@Service
public class ConversationSummaryService {
    private static final Logger logger = LoggerFactory.getLogger(ConversationSummaryService.class);
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyyMMdd HHmmss");

    private final ChatMemoryService chatMemoryService;
    private final ChatClient chatClient;

    public ConversationSummaryService(ChatMemoryService chatMemoryService,
                                     ChatClient.Builder chatClientBuilder) {
        this.chatMemoryService = chatMemoryService;
        this.chatClient = chatClientBuilder.build();
    }

    public String summarizeAndSave(String conversationId) {
        logger.info("Summarizing conversation: {}", conversationId);

        // 1. Get session messages and existing preferences
        List<Message> messages = chatMemoryService.getSessionMemory().get(conversationId);
        if (messages.isEmpty()) {
            return "No conversation to summarize";
        }

        List<Message> existingPrefs = chatMemoryService.getPreferencesMemory().get(conversationId + "_preferences");
        String existingPrefsText = existingPrefs.isEmpty() ? "" : existingPrefs.get(0).getText();

        // 2. Convert messages to text
        String messagesText = messages.stream()
            .filter(msg -> msg.getText() != null && !msg.getText().isEmpty())
            .map(msg -> msg.getMessageType() + ": " + msg.getText())
            .reduce((a, b) -> a + "\n" + b)
            .orElse("");

        if (messagesText.isEmpty()) {
            return "No valid conversation content to summarize";
        }

        logger.info("Summarizing {} characters", messagesText.length());

        // 3. Generate AI summary (preferences + context)
        String preferencesPrompt = existingPrefsText.isEmpty()
            ? "Extract static user information (name, email, preferences). If none, return empty."
            : "Merge preferences. Keep existing:\n" + existingPrefsText +
              "\nAdd new from conversation. Update only if explicitly changed. Keep existing if unchanged.";

        var chatResponse = chatClient.prompt()
            .user("Analyze this conversation and provide TWO separate summaries:\n\n" +
                  "PREFERENCES:\n" + preferencesPrompt + "\n\n" +
                  "CONTEXT:\n" +
                  "Summarize: topics discussed, questions asked, decisions made, pending items.\n" +
                  "DO NOT include: prices, dates, flight numbers, hotel names, policies.\n\n" +
                  "Output format:\n===PREFERENCES===\n[preferences]\n===CONTEXT===\n[context]\n\n" +
                  "Conversation:\n" + messagesText)
            .call()
            .chatResponse();

        String response = (chatResponse != null &&
            chatResponse.getResult() != null &&
            chatResponse.getResult().getOutput() != null)
            ? chatResponse.getResult().getOutput().getText()
            : null;

        if (response == null || response.trim().isEmpty()) {
            throw new RuntimeException("Failed to generate summary");
        }

        // 4. Parse preferences and context
        String preferences = extractSection(response, "===PREFERENCES===", "===CONTEXT===");
        String context = extractSection(response, "===CONTEXT===", null);

        if (context.isEmpty() && preferences.isEmpty()) {
            context = response; // Fallback: use full response as context
        }

        logger.info("Extracted preferences: {} chars, context: {} chars", preferences.length(), context.length());

        // 5. Save to memory tiers
        String timestamp = LocalDateTime.now().format(TIMESTAMP_FORMAT);

        if (!preferences.isEmpty()) {
            chatMemoryService.getPreferencesMemory()
                .add(conversationId + "_preferences", new AssistantMessage(preferences));
        }

        if (!context.isEmpty()) {
            chatMemoryService.getContextMemory()
                .add(conversationId + "_context", new AssistantMessage("[" + timestamp + "] " + context));
        }

        // 6. Clear session memory
        chatMemoryService.getSessionMemory().clear(conversationId);
        logger.info("Summary saved, session cleared");

        return formatSummaryResponse(timestamp, preferences, context);
    }

    private String extractSection(String response, String startMarker, String endMarker) {
        try {
            if (!response.contains(startMarker)) {
                return "";
            }
            int start = response.indexOf(startMarker) + startMarker.length();
            int end = endMarker != null && response.contains(endMarker)
                ? response.indexOf(endMarker)
                : response.length();
            return end > start ? response.substring(start, end).trim() : "";
        } catch (Exception e) {
            logger.warn("Failed to extract section: {}", startMarker, e);
            return "";
        }
    }

    private String formatSummaryResponse(String timestamp, String preferences, String context) {
        return "**Summary:** [" + timestamp + "]\n\n" +
               "**Preferences:**\n" + (preferences.isEmpty() ? "None" : preferences) +
               "\n\n**Context:**\n" + context;
    }
}
