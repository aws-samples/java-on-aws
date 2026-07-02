package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.InMemoryChatMemoryRepository;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

@RestController
@RequestMapping("/memory")
public class MemoryAgentController {
    private ChatClient chatClient;
    private final ChatClient.Builder chatClientBuilder;
    private final MessageChatMemoryAdvisor promptChatMemoryAdvisor;

    public MemoryAgentController(ChatClient chatClient, ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClient;
        this.chatClientBuilder = chatClientBuilder;
        var memory =
                MessageWindowChatMemory.builder()
                        .chatMemoryRepository(new InMemoryChatMemoryRepository())
                        .build();
        this.promptChatMemoryAdvisor = MessageChatMemoryAdvisor.builder(memory).build();
    }

    @PostMapping("/chat")
    public String chat(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .advisors(promptChatMemoryAdvisor)
                .advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, "logged-user-account"))
                .user(prompt)
                .call()
                .content();
    }

    @PostMapping("/chat/stream")
    public Flux<String> chatStream(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .advisors(promptChatMemoryAdvisor)
                .advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, "logged-user-account"))
                .user(prompt)
                .stream()
                .content();
    }

    @PostMapping("/model")
    public void updateModel(@RequestParam String model) {
        chatClient = chatClientBuilder
                .defaultOptions(ChatOptions.builder().model(model)).build();
    }
}