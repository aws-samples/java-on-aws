package com.example.agent;

import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    private final ChatClient chatClient;

    public ChatService(ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClientBuilder
            .build();
    }

    @AgentCoreInvocation
    public Flux<String> chat(ChatRequest request) {
        return chatClient.prompt().user(request.prompt()).stream().content();
    }
}
