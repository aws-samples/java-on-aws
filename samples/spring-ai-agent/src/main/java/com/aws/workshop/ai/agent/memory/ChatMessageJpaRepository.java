package com.aws.workshop.ai.agent.memory;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface ChatMessageJpaRepository extends JpaRepository<ChatMessageEntity, Long> {

    List<ChatMessageEntity> findByConversationId(String conversationId);

    void deleteByConversationId(String conversationId);

    @Query("SELECT DISTINCT m.conversationId FROM ChatMessageEntity m WHERE m.conversationId IS NOT NULL")
    List<String> findDistinctConversationIds();
}
