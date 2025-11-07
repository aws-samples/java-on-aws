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
    private final ChatResponseExtractor responseExtractor;

    public static final String SYSTEM_PROMPT = """
        You are a helpful and honest AI Agent for our company.
        You can help with questions related to travel and expenses.

        Follow these guidelines strictly:
        1. TOOLS FIRST: For real-time information (flights, weather, bookings, currency), ALWAYS use the available tools.
        2. RAG CONTEXT: Use provided context for company policies and static information only.
        3. ACCURACY FIRST: Only provide information you are confident about.
        4. ADMIT UNCERTAINTY: If unsure, respond with "I don't know" or "I'm not certain about that."
        5. NO SPECULATION: Do not guess or make up information.
        6. TABLE FORMAT: Always use clean markdown tables for structured data presentation.

        Priority order:
        - Dynamic data (flights, weather, prices) → Use tools
        - Company policies → Use provided context
        - Unknown → Say "I don't know"
        """;

    public ChatService(ChatResponseExtractor responseExtractor,
                      ChatMemoryService chatMemoryService,
                      VectorStore vectorStore,
                      DateTimeService dateTimeService,
                      WeatherService weatherService,
                      ToolCallbackProvider tools,
                      ChatClient.Builder chatClientBuilder) {
        this.responseExtractor = responseExtractor;
        this.chatClient = chatClientBuilder
                .defaultSystem(SYSTEM_PROMPT)
                .defaultAdvisors(
                        QuestionAnswerAdvisor.builder(vectorStore).build()
                )
                .defaultTools(dateTimeService, weatherService)
                .defaultToolCallbacks(tools)
                .build();

        this.chatMemoryService = chatMemoryService;
        logger.info("ChatService initialized with embedded ChatClient");
    }

    public Flux<String> processChat(String prompt) {
        logger.info("Processing streaming chat request - prompt: '{}'", prompt);
        try {
            // Simple streaming without memory:
            // return chatClient
            //     .prompt().user(prompt)
            //     .stream()
            //     .content();
            return chatMemoryService.callWithMemory(chatClient, prompt);
        } catch (Exception e) {
            logger.error("Error processing streaming chat request", e);
            return Flux.just("I don't know - there was an error processing your request.");
        }
    }

    public String extractTextFromResponse(org.springframework.ai.chat.model.ChatResponse chatResponse) {
        return responseExtractor.extractText(chatResponse);
    }
}
