package com.example.ai.agent.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.vectorstore.VectorStore;
import com.example.ai.agent.tool.DateTimeService;
import org.springframework.ai.tool.ToolCallbackProvider;

@Service
public class ChatService {
    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;
    private final ChatMemoryService chatMemoryService;

    public static final String SYSTEM_PROMPT = """
        You are a helpful and honest AI Agent for our company.
        You can help with questions related to travel and expenses.

        Follow these guidelines strictly:
        1. ACCURACY FIRST: Only provide information you are confident about based on your training data.
        2. ADMIT UNCERTAINTY: If you are unsure about any fact, detail, or answer, respond with "I don't know" or "I'm not certain about that."
        3. NO SPECULATION: Do not guess, speculate, or make up information. It's better to say "I don't know" than to provide potentially incorrect information.
        4. PARTIAL KNOWLEDGE: If you know some aspects of a topic but not others, clearly state what you know and what you don't know.
        5. SOURCES: Do not claim to have access to real-time information, current events after your training cutoff, or specific databases unless explicitly provided.
        6. TABLE FORMAT: Always use clean markdown tables for structured data presentation.

        Example responses:
        - "I don't know the current stock price of that company."
        - "I'm not certain about the specific details of that recent event."
        - "I don't have enough information to answer that question accurately."
        Remember: Being honest about limitations builds trust. Always choose "I don't know" over potentially incorrect information.
        """;

    public ChatService(ChatMemoryService chatMemoryService,
                      VectorStore vectorStore,
                      DateTimeService dateTimeService,
                      ToolCallbackProvider tools,
                      ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClientBuilder
                .defaultSystem(SYSTEM_PROMPT)
                .defaultAdvisors(
                        QuestionAnswerAdvisor.builder(vectorStore).build()
                )
                .defaultTools(dateTimeService)
                .defaultToolCallbacks(tools)
                .build();

        this.chatMemoryService = chatMemoryService;
        logger.info("ChatService initialized with embedded ChatClient");
    }

    public String processChat(String prompt) {
        logger.info("Processing text chat request - prompt: '{}'", prompt);
        try {
            // var chatResponse = chatClient
            //     .prompt().user(prompt)
            //     .call()
            //     .chatResponse();
            var chatResponse = chatMemoryService.callWithMemory(chatClient, prompt);
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
