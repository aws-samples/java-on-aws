package com.example.ai.agent.controller;

import com.example.ai.agent.service.ChatService;
import com.example.ai.agent.service.ChatMemoryService;
import com.example.ai.agent.service.ConversationSummaryService;
import com.example.ai.agent.service.DocumentChatService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import reactor.core.publisher.Flux;
import java.security.Principal;

@RestController
@RequestMapping("api/chat")
public class ChatController {
    private static final Logger logger = LoggerFactory.getLogger(ChatController.class);

    private final ChatService chatService;
    private final DocumentChatService documentChatService;
    private final ConversationSummaryService summaryService;
    private final ChatMemoryService chatMemoryService;

    public ChatController(ChatService chatService,
                         DocumentChatService documentChatService,
                         ConversationSummaryService summaryService,
                         ChatMemoryService chatMemoryService) {
        this.chatService = chatService;
        this.documentChatService = documentChatService;
        this.summaryService = summaryService;
        this.chatMemoryService = chatMemoryService;
    }

    @PostMapping(value = "message", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    public Flux<String> chat(@RequestBody ChatRequest request, Principal principal) {
        String userId = getUserId(request.userId(), principal);
        chatMemoryService.setCurrentUserId(userId);

        if (hasFile(request)) {
            return documentChatService.processDocument(request.prompt(), request.fileBase64(), request.fileName());
        } else {
            return chatService.processChat(request.prompt());
        }
    }

    @PostMapping("summarize")
    public String summarize(@RequestBody(required = false) SummarizeRequest request, Principal principal) {
        try {
            String userId = getUserId(request != null ? request.userId() : null, principal);
            return summaryService.summarizeAndSave(userId);
        } catch (Exception e) {
            logger.error("Error summarizing conversation", e);
            return "Failed to summarize conversation. Please try again.";
        }
    }

    private String getUserId(String requestUserId, Principal principal) {
        if (principal != null) {
            return principal.getName();
        }
        return requestUserId != null ? requestUserId : "user1";
    }

    private boolean hasFile(ChatRequest request) {
        return request.fileBase64() != null && !request.fileBase64().trim().isEmpty();
    }

    public record ChatRequest(String prompt, String userId, String fileBase64, String fileName) {}
    public record SummarizeRequest(String userId) {}
}
