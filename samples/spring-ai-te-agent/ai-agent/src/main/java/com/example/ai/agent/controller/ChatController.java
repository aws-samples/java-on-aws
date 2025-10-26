package com.example.ai.agent.controller;

import com.example.ai.agent.service.ChatService;
import com.example.ai.agent.service.DocumentChatService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("api")
public class ChatController {
    private final ChatService chatService;
    private final DocumentChatService documentChatService;

    public ChatController(ChatService chatService, DocumentChatService documentChatService) {
        this.chatService = chatService;
        this.documentChatService = documentChatService;
    }

    @PostMapping("chat")
    public String chat(@RequestBody ChatRequest request) {
        if (hasFile(request)) {
            return documentChatService.processDocument(request.prompt(), request.fileBase64(), request.fileName());
        } else {
            return chatService.processChat(request.prompt());
        }
    }

    private boolean hasFile(ChatRequest request) {
        return request.fileBase64() != null && !request.fileBase64().trim().isEmpty();
    }

    public record ChatRequest(String prompt, String fileBase64, String fileName) {}
}
