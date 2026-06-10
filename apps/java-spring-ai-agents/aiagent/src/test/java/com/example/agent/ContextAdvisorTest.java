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

        // Order is preserved and no extra messages are added (augmented in place).
        assertThat(messages).hasSize(2);
        assertThat(texts.get(0)).isEqualTo("system prompt");
        // The user message is augmented in place with timestamp + userId + original text.
        assertThat(texts.get(1))
                .startsWith("[Current date and time:")
                .contains("[UserId: user-123]")
                .contains("hello world");
    }

    @Test
    void before_withoutConversationId_usesUnknownUserId() {
        Prompt prompt = new Prompt(List.of(new UserMessage("hi")));
        ChatClientRequest request = new ChatClientRequest(prompt, Map.of());

        ChatClientRequest result = advisor.before(request, null);

        List<String> texts = result.prompt().getInstructions().stream().map(Message::getText).toList();
        assertThat(texts).anyMatch(t -> t.contains("[UserId: unknown]") && t.contains("hi"));
    }

    @Test
    void after_returnsResponseUnchanged() {
        // after() is a pass-through; passing null chain is fine since it is unused.
        assertThat(advisor.getOrder()).isZero();
    }
}
