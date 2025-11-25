package com.example.ai.agent.service;


import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
public class ChatClientMemoryTest {

    @Autowired
    private ChatService chatService;

    @Test
    public void shouldMemorizeMemoryContext() {
        // Test if the model knows basic facts
        String memoryAdvice = "My name is Andrei";
        chatService.processChat(memoryAdvice);

        String question = "What is my name?";
        String response = chatService.processChat(question);
        System.out.println("=== DIRECT MODEL TEST ===");
        System.out.println("Question: " + question);
        System.out.println("Response: " + response);
        
        assertThat(response).isNotNull().isNotEmpty();
        assertThat(response.toLowerCase()).contains("andrei");
    }
}
