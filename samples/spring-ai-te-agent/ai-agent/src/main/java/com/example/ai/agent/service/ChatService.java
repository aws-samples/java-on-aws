package com.example.ai.agent.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.example.ai.agent.model.ChatRequest;
import com.example.ai.agent.tool.DateTimeService;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.ai.tool.ToolCallbackProvider;

@Service
public class ChatService {
    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;
    private final ChatMemoryService chatMemoryService;

    public ChatService(ChatClient.Builder chatClientBuilder,
                      ChatMemoryService chatMemoryService,
                      VectorStore vectorStore,
                      DateTimeService dateTimeService,
                      ToolCallbackProvider tools) {
        this.chatClient = chatClientBuilder
                .defaultSystem(Prompts.SYSTEM_PROMPT)
                .defaultAdvisors(
                        QuestionAnswerAdvisor.builder(vectorStore).build()
                )
                .defaultTools(dateTimeService)
                .defaultToolCallbacks(tools)
                .build();

        this.chatMemoryService = chatMemoryService;
        logger.info("ChatService initialized with embedded ChatClient");
    }

    public String processChat(ChatRequest request) {
        logger.info("Processing text chat request - prompt: '{}'", request.prompt());
        try {
            var chatResponse = chatMemoryService.callWithMemory(chatClient, request);
            return extractTextFromResponse(chatResponse);
        } catch (Exception e) {
            logger.error("Error processing chat request", e);
            return "I don't know - there was an error processing your request.";
        }
    }

    public String extractTextFromResponse(org.springframework.ai.chat.model.ChatResponse chatResponse) {
        if (chatResponse != null) {
            // First try the standard approach
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
        }

        return "I don't know - no response received.";
    }
}
