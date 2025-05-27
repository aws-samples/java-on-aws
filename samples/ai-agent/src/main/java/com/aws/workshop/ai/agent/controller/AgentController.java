package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.web.bind.annotation.*;
import software.amazon.awssdk.utils.StringInputStream;

import java.io.InputStream;
import java.util.Objects;

@RestController
public class AgentController {
    private ChatClient chatClient;
    private final ChatClient.Builder chatClientBuilder;

    public AgentController(ChatClient chatClient, ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClient;
        this.chatClientBuilder = chatClientBuilder;
    }

    @PostMapping("/chat")
    public String chat(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .user(prompt)
                .call()
                .content();
    }

    @PostMapping("/chat/stream")
    public InputStream chatStream(@RequestBody String prompt) {
        return new StringInputStream(Objects.requireNonNull(chatClient
                .prompt()
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
