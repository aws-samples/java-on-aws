package com.aws.workshop.ai.agent.controller;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(RagPgVectorAgentController.class)
class RagPgVectorAgentControllerTest {
    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private ChatClient chatClient;
    @MockitoBean
    private ChatClient.Builder chatClientBuilder;
    @MockitoBean
    private VectorStore vectorStore;
    @MockitoBean
    private QuestionAnswerAdvisor ragAdvisor;


    @Test
    void shouldLoadVectorStore() throws Exception {
        mockMvc.perform(post("/rag-pgvector/load")
                        .contentType(MediaType.TEXT_PLAIN)
                        .content("my content"))
                .andExpect(status().isOk());

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<Document>> documentArgumentCaptor = ArgumentCaptor.forClass(List.class);
        verify(vectorStore).add(documentArgumentCaptor.capture());
        assertThat(documentArgumentCaptor.getValue()).hasSize(1);
        assertThat(documentArgumentCaptor.getValue().getFirst().getText()).isEqualTo("my content");
    }
}