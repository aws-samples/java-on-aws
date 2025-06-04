package com.aws.workshop.ai.agent.memory;

import org.springframework.ai.chat.memory.ChatMemoryRepository;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.MessageType;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.stream.Collectors;

@Repository
public class ExternalChatMemoryRepository implements ChatMemoryRepository {

    private final ChatMessageJpaRepository jpaRepository;

    public ExternalChatMemoryRepository(ChatMessageJpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    @NonNull
    public List<String> findConversationIds() {
        return jpaRepository.findDistinctConversationIds();
    }

    @Override
    @NonNull
    public List<Message> findByConversationId(@NonNull String conversationId) {
        return jpaRepository.findByConversationId(conversationId)
                .stream()
                // Currently only memory for user messages is supported
                .filter(entity -> MessageType.USER.name().equals(entity.getType()))
                .map(entity -> UserMessage.builder()
                                        .text(entity.getText())
                                        .build())
                .collect(Collectors.toList());
    }

    @Override
    public void saveAll(@NonNull String conversationId, List<Message> messages) {
        List<ChatMessageEntity> entities = messages.stream()
                // Currently only memory for user messages is supported
                .filter(msg -> MessageType.USER == msg.getMessageType())
                .map(msg -> new ChatMessageEntity(
                        conversationId,
                        msg.getText(),
                        Instant.now(),
                        msg.getMessageType().name())
                ).toList();

        jpaRepository.saveAll(entities);
    }

    @Override
    public void deleteByConversationId(@NonNull String conversationId) {
        jpaRepository.deleteByConversationId(conversationId);
    }
}