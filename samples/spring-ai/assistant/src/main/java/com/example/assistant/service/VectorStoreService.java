package com.example.assistant.service;

import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.stereotype.Service;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Service
public class VectorStoreService {
    private static final Logger logger = LoggerFactory.getLogger(VectorStoreService.class);

    private final VectorStore vectorStore;

    public VectorStoreService(VectorStore vectorStore) {
        this.vectorStore = vectorStore;
    }

    public void addContent(String content) {
        logger.info("Loading content to vector store - length: {}", content.length());
        vectorStore.add(List.of(new Document(content)));
        logger.info("Content loaded successfully");
    }
}
