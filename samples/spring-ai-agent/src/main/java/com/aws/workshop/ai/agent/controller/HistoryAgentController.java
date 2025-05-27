package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.PromptChatMemoryAdvisor;
import org.springframework.ai.chat.memory.InMemoryChatMemoryRepository;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.web.bind.annotation.*;
import software.amazon.awssdk.utils.StringInputStream;

import java.io.InputStream;
import java.util.Objects;

@RestController
@RequestMapping("/memory")
public class HistoryAgentController {
    private ChatClient chatClient;
    private final ChatClient.Builder chatClientBuilder;
    private final PromptChatMemoryAdvisor promptChatMemoryAdvisor;

    public HistoryAgentController(ChatClient chatClient, ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClient;
        this.chatClientBuilder = chatClientBuilder;
        var memory =
                MessageWindowChatMemory.builder()
                        .chatMemoryRepository(new InMemoryChatMemoryRepository())
                        .build();
        this.promptChatMemoryAdvisor = PromptChatMemoryAdvisor.builder(memory).build();
    }

    @PostMapping("/chat")
    public String chat(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .advisors(promptChatMemoryAdvisor)
                .user(prompt)
                .call()
                .content();
    }

    @PostMapping("/chat/stream")
    public InputStream chatStream(@RequestBody String prompt) {
        return new StringInputStream(Objects.requireNonNull(chatClient
                .prompt()
                .advisors(promptChatMemoryAdvisor)
                .user(prompt)
                .call()
                .content()));
    }

    @PostMapping("/model")
    public void updateModel(@RequestParam String model) {
        ChatOptions chatOptions = ChatOptions.builder()
                .model(model).build();
        chatClient = chatClientBuilder
                .defaultOptions(chatOptions).build();
    }
}
