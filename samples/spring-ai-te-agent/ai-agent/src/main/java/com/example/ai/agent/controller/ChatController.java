package com.example.ai.agent.controller;

import com.example.ai.agent.model.ChatRequest;
import com.example.ai.agent.service.ChatServiceInterface;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("api")
public class ChatController {
    private final ChatServiceInterface chatService;

    public ChatController(ChatServiceInterface chatService) {
        this.chatService = chatService;
    }

    @PostMapping("chat")
    public String chat(@RequestBody ChatRequest request) {
        return chatService.processChat(request);
    }
}
