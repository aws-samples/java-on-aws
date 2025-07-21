package com.aws.workshop.ai.agent.controller;

import com.aws.workshop.ai.agent.memory.ExternalChatMemoryRepository;
import org.junit.jupiter.api.Test;
import org.mockito.Answers;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import reactor.core.publisher.Flux;

import java.util.function.Consumer;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(MemoryAgentController.class)
class MemoryAgentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean(answers = Answers.RETURNS_DEEP_STUBS)
    private ChatClient chatClient;

    @MockitoBean
    private ChatClient.Builder chatClientBuilder;

    @MockitoBean
    private ExternalChatMemoryRepository chatMemoryRepository;

    @Test
    void shouldHandleChatRequest() throws Exception {
        // Given
        String request = "Hello AI";
        String response = "Hello Human";

        when(chatClient
                .prompt()
                .advisors(any(Advisor.class))
                .advisors(any(Consumer.class))
                .user(request)
                .call()
                .content()).thenReturn(response);

        // When & Then
        mockMvc.perform(post("/memory/chat")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(request))
                .andExpect(status().isOk())
                .andExpect(content().string(response));
    }

    @Test
    void shouldHandleChatStreamRequest() throws Exception {
        // Given
        String request = "Hello AI";
        String response = "Hello Human";

        when(chatClient
                .prompt()
                .advisors(any(Advisor.class))
                .advisors(any(Consumer.class))
                .user(request)
                .stream()
                .content()).thenReturn(Flux.just(response));

        // When & Then
        mockMvc.perform(post("/memory/chat/stream")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(request))
                .andExpect(status().isOk())
                .andExpect(content().string("Hello Human"));
    }

    @Test
    void shouldUpdateModel() throws Exception {
        // Given
        String modelName = "test-model";
        when(chatClientBuilder.defaultOptions(any(ChatOptions.class))).thenReturn(chatClientBuilder);
        when(chatClientBuilder.build()).thenReturn(chatClient);

        // When & Then
        mockMvc.perform(post("/memory/model")
                        .param("model", modelName))
                .andExpect(status().isOk());

        verify(chatClientBuilder).defaultOptions(argThat(options ->
                (options.getModel() != null) && options.getModel().equals(modelName)));
        verify(chatClientBuilder).build();
    }
}
