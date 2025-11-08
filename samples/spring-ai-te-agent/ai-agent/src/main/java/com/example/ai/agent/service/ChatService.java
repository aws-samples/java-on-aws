package com.example.ai.agent.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.vectorstore.VectorStore;
import com.example.ai.agent.tool.DateTimeService;
import com.example.ai.agent.tool.WeatherService;
import org.springframework.ai.tool.ToolCallbackProvider;

@Service
public class ChatService {
    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

    private final ChatClient chatClient;
    private final ChatMemoryService chatMemoryService;

    public static final String SYSTEM_PROMPT = """
        You are a helpful AI Agent for travel and expenses.

        Guidelines:
        1. Use markdown tables for structured data
        2. If unsure, say "I don't know"
        3. Use provided context for company policies
        4. Use tools for dynamic data (flights, weather, bookings, currency)
        """;

    public ChatService(ChatMemoryService chatMemoryService,
                      VectorStore vectorStore,
                      DateTimeService dateTimeService,
                      WeatherService weatherService,
                      ToolCallbackProvider tools,
                      ChatClient.Builder chatClientBuilder) {

        // Build ChatClient with RAG, tools, and memory
        this.chatClient = chatClientBuilder
                .defaultSystem(SYSTEM_PROMPT)
                .defaultAdvisors(QuestionAnswerAdvisor.builder(vectorStore).build())  // RAG for policies
                .defaultTools(dateTimeService, weatherService)  // Custom tools
                .defaultToolCallbacks(tools)  // Auto-registered tools from MCP
                .build();

        this.chatMemoryService = chatMemoryService;
    }

    public Flux<String> processChat(String prompt) {
        logger.info("Processing chat: '{}'", prompt);
        try {
            // Simple streaming without memory:
            // return chatClient
            //     .prompt().user(prompt)
            //     .stream()
            //     .content();
            return chatMemoryService.callWithMemory(chatClient, prompt);
        } catch (Exception e) {
            logger.error("Error processing chat", e);
            return Flux.just("I don't know - there was an error processing your request.");
        }
    }
}
