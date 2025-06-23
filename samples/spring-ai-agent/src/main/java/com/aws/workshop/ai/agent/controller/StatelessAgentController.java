package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

@RestController
public class StatelessAgentController {
    private ChatClient chatClient;
    private final ChatClient.Builder chatClientBuilder;

    public StatelessAgentController(ChatClient chatClient, ChatClient.Builder chatClientBuilder) {
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
    public Flux<String> chatStream(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .user(prompt)
                .stream()
                .content();
    }

    @PostMapping("/model")
    public void updateModel(@RequestParam String model) {
        var chatOptions = ChatOptions.builder()
                .model(model).build();
        chatClient = chatClientBuilder
                .defaultOptions(chatOptions).build();
    }
}
