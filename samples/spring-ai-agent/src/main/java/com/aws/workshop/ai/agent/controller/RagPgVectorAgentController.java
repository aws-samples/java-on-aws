package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.utils.StringInputStream;

import java.io.InputStream;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

@RestController
@RequestMapping("/rag-pgvector")
public class RagPgVectorAgentController {
    private ChatClient chatClient;
    private final ChatClient.Builder chatClientBuilder;
    private final VectorStore vectorStore;
    private final QuestionAnswerAdvisor ragAdvisor;

    public RagPgVectorAgentController(ChatClient chatClient, VectorStore vectorStore, ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClient;
        this.chatClientBuilder = chatClientBuilder;
        this.vectorStore = vectorStore;
        ragAdvisor = QuestionAnswerAdvisor.builder(vectorStore).build();
    }

    @PostMapping("/chat")
    public String chat(@RequestBody String prompt) {
        var content = chatClient
                .prompt()
                .advisors(ragAdvisor)
                .user(prompt)
                .call()
                .content();

        vectorStore.add(List.of(new Document(content)));

        return content;
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
