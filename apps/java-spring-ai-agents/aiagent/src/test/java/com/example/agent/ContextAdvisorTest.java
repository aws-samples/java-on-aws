package com.example.agent;

import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.client.ChatClientRequest;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.prompt.Prompt;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pure unit tests for {@link ContextAdvisor}. No Spring context, no AWS credentials required.
 * Verifies the prompt is augmented with the current timestamp and the resolved user id.
 */
class ContextAdvisorTest {

    private final ContextAdvisor advisor = new ContextAdvisor();

    @Test
    void before_withConversationId_injectsTimestampAndUserId() {
        Prompt prompt = new Prompt(List.of(
                new SystemMessage("system prompt"),
                new UserMessage("hello world")));
        ChatClientRequest request = new ChatClientRequest(
                prompt, Map.of(ChatMemory.CONVERSATION_ID, "user-123:session-abc"));

        ChatClientRequest result = advisor.before(request, null);

        List<Message> messages = result.prompt().getInstructions();
        List<String> texts = messages.stream().map(Message::getText).toList();

        // Original system message is preserved.
        assertThat(texts).anyMatch(t -> t.equals("system prompt"));
        // Timestamp message is added.
        assertThat(texts).anyMatch(t -> t.startsWith("[Current date and time:"));
        // User id is extracted from the conversation id (before the colon) and the original text retained.
        assertThat(texts).anyMatch(t -> t.startsWith("[UserId: user-123]") && t.contains("hello world"));
        // The bare original user message was replaced (not left as plain "hello world").
        assertThat(texts).doesNotContain("hello world");
    }

    @Test
    void before_withoutConversationId_usesUnknownUserId() {
        Prompt prompt = new Prompt(List.of(new UserMessage("hi")));
        ChatClientRequest request = new ChatClientRequest(prompt, Map.of());

        ChatClientRequest result = advisor.before(request, null);

        List<String> texts = result.prompt().getInstructions().stream().map(Message::getText).toList();
        assertThat(texts).anyMatch(t -> t.startsWith("[UserId: unknown]") && t.contains("hi"));
    }

    @Test
    void after_returnsResponseUnchanged() {
        // after() is a pass-through; passing null chain is fine since it is unused.
        assertThat(advisor.getOrder()).isZero();
    }
}
