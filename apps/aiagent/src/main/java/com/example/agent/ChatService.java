package com.example.agent;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.InMemoryChatMemoryRepository;

@Service
public class ChatService {

    private static final String DEFAULT_SYSTEM_PROMPT = """
        You are a helpful AI assistant.
        Be friendly, helpful, and concise in your responses.
        """;

    private final ChatClient chatClient;

    public ChatService(ChatClient.Builder chatClientBuilder) {

        var chatMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(new InMemoryChatMemoryRepository())
            .maxMessages(100)
            .build();

        this.chatClient = chatClientBuilder
            .defaultSystem(DEFAULT_SYSTEM_PROMPT)
            .defaultAdvisors(
                MessageChatMemoryAdvisor.builder(chatMemory).build())
            .defaultTools(new DateTimeTools(), new WeatherTools())
            .build();
    }

    public Flux<String> chat(String prompt, String username) {
        return chatClient.prompt().user(prompt)
            .advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, username))
            .stream().content();
    }
}