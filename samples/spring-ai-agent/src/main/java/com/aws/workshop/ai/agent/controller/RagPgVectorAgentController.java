package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.ai.observation.conventions.VectorStoreProvider;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.utils.StringInputStream;

import java.io.InputStream;
import java.util.Objects;

@RestController
@RequestMapping("/rag-pgvector")
public class RagPgVectorAgentController {
    private ChatClient chatClient;
    private final ChatClient.Builder chatClientBuilder;
    private final QuestionAnswerAdvisor ragAdvisor;

    public RagPgVectorAgentController(ChatClient chatClient, VectorStore vectorStore, ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClient;
        this.chatClientBuilder = chatClientBuilder;
        ragAdvisor = QuestionAnswerAdvisor.builder(vectorStore).build();
    }

    @PostMapping("/chat")
    public String chat(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .advisors(ragAdvisor)
                .user(prompt)
                .call()
                .content();
    }

    @PostMapping("/chat/stream")
    public InputStream chatStream(@RequestBody String prompt) {
        return new StringInputStream(Objects.requireNonNull(chatClient
                .prompt()
                .advisors(ragAdvisor)
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
