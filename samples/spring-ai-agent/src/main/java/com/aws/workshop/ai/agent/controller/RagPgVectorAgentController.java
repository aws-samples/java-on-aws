package com.aws.workshop.ai.agent.controller;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

import java.util.List;

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
        return chatClient
                .prompt()
                .advisors(ragAdvisor)
                .user(prompt)
                .call()
                .content();
    }

    @PostMapping("/load")
    public void loadDataToVectorStore(@RequestBody String content) {
        vectorStore.add(List.of(new Document(content)));
    }

    @PostMapping("/chat/stream")
    public Flux<String> chatStream(@RequestBody String prompt) {
        return chatClient
                .prompt()
                .advisors(ragAdvisor)
                .user(prompt)
                .stream()
                .content();
    }

    @PostMapping("/model")
    public void updateModel(@RequestParam String model) {
        ChatOptions chatOptions = ChatOptions.builder()
                .model(model).build();
        chatClient = chatClientBuilder
                .defaultOptions(chatOptions).build();
    }
}
