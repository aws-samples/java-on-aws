package com.aws.workshop.ai.agent.memory;

import jakarta.persistence.*;

import java.time.Instant;

@Entity
@Table(name = "chat_messages")
@SuppressWarnings("unused")
public class ChatMessageEntity {
        @Id
        @GeneratedValue(strategy = GenerationType.IDENTITY)
        private Long id;

        private String conversationId;

        private String text;

        private Instant timestamp;

        private String type;

        public ChatMessageEntity() {
        }

        public ChatMessageEntity(String conversationId, String text, Instant timestamp, String type) {
            this.conversationId = conversationId;
            this.text = text;
            this.timestamp = timestamp;
            this.type = type;
        }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getConversationId() {
        return conversationId;
    }

    public void setConversationId(String conversationId) {
        this.conversationId = conversationId;
    }

    public String getText() {
        return text;
    }

    public void setText(String text) {
        this.text = text;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }
}