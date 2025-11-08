package com.example.ai.agent.controller;

import com.example.ai.agent.service.ChatService;
import com.example.ai.agent.service.ChatMemoryService;
import com.example.ai.agent.service.ConversationSummaryService;
import com.example.ai.agent.service.DocumentChatService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import reactor.core.publisher.Flux;
import java.security.Principal;

@RestController
@RequestMapping("api/chat")
public class ChatController {
    private static final Logger logger = LoggerFactory.getLogger(ChatController.class);

    private final ChatService chatService;
    private final ChatMemoryService chatMemoryService;
    private final ConversationSummaryService summaryService;
    private final DocumentChatService documentChatService;

    public ChatController(ChatMemoryService chatMemoryService,
                         ConversationSummaryService summaryService,
                         DocumentChatService documentChatService,
                         ChatService chatService) {
        this.chatService = chatService;
        this.chatMemoryService = chatMemoryService;
        this.summaryService = summaryService;
        this.documentChatService = documentChatService;
    }

    @PostMapping(value = "message", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    public Flux<String> chat(@RequestBody ChatRequest request, Principal principal) {
        String userId = getUserId(request.userId(), principal);
        chatMemoryService.setCurrentUserId(userId);

        // Route to document analysis or regular chat
        return hasFile(request)
            ? documentChatService.processDocument(request.prompt(), request.fileBase64(), request.fileName())
            : chatService.processChat(request.prompt());
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
        // Production: use authenticated user from Spring Security
        if (principal != null) {
            return principal.getName();
        }
        // Development: use provided userId or default
        return requestUserId != null ? requestUserId : "user1";
    }

    private boolean hasFile(ChatRequest request) {
        return request.fileBase64() != null && !request.fileBase64().trim().isEmpty();
    }

    public record ChatRequest(String prompt, String userId, String fileBase64, String fileName) {}
    public record SummarizeRequest(String userId) {}
}
