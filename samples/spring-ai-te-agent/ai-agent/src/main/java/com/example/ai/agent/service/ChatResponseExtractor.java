package com.example.ai.agent.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.stereotype.Component;

/**
 * Utility for extracting text content from ChatResponse objects.
 * Handles both standard responses and models with reasoning content.
 */
@Component
public class ChatResponseExtractor {
    private static final Logger logger = LoggerFactory.getLogger(ChatResponseExtractor.class);

    public String extractText(ChatResponse chatResponse) {
        if (chatResponse == null) {
            return "I don't know - no response received.";
        }

        // Try standard approach first
        String text = chatResponse.getResult().getOutput().getText();
        if (text != null && !text.isEmpty()) {
            return text;
        }

        // Fallback: iterate through generations for models with reasoning content
        if (!chatResponse.getResults().isEmpty()) {
            for (var generation : chatResponse.getResults()) {
                String textContent = generation.getOutput().getText();
                if (textContent != null && !textContent.isEmpty()) {
                    logger.info("Found text content: '{}'", textContent);
                    return textContent;
                }
            }
        }

        return "I don't know - no response received.";
    }
}
