package com.example.agent;

import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private final ChatClient chatClient;

    // >> The system prompt defines the persona of the AI agent
    private static final String SYSTEM_PROMPT = """
        You are the travel and expense assistant of the company. You help employees plan business trips,
        follow the travel and expense policies, and keep track of their trips and expenses.

        Rules:
        - Focus on business travel and expenses.
        - Ask for missing details such as dates, origin, or destination instead of guessing them.
        - Do not invent policy rules; say so when you are not sure.

        Format:
        - Be friendly and concise.
        - Use tables to compare options.
        """;
    // <<

    public ChatService(ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClientBuilder
            // >> `defaultSystem()` applies the system prompt to all requests
            .defaultSystem(SYSTEM_PROMPT)
            // <<
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request) {
        return chatClient.prompt().user(request.prompt()).stream().content();
    }
}
