package com.example.agent;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for the {@link ChatRequest} record's {@code hasFile()} logic. No credentials required.
 */
class ChatRequestTest {

    @Test
    void hasFile_trueWhenBothFieldsPresent() {
        assertThat(new ChatRequest("prompt", "ZmlsZQ==", "doc.pdf").hasFile()).isTrue();
    }

    @Test
    void hasFile_falseWhenBase64Missing() {
        assertThat(new ChatRequest("prompt", null, "doc.pdf").hasFile()).isFalse();
        assertThat(new ChatRequest("prompt", "", "doc.pdf").hasFile()).isFalse();
    }

    @Test
    void hasFile_falseWhenFileNameMissing() {
        assertThat(new ChatRequest("prompt", "ZmlsZQ==", null).hasFile()).isFalse();
        assertThat(new ChatRequest("prompt", "ZmlsZQ==", "").hasFile()).isFalse();
    }

    @Test
    void hasFile_falseWhenPromptOnly() {
        assertThat(new ChatRequest("just a prompt", null, null).hasFile()).isFalse();
    }
}
