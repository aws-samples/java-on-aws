package com.example.ai.agent.controller;

import com.example.ai.agent.service.ChatService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("api")
public class ChatController {

    private final ChatService chatService;

    public ChatController(ChatService chatService) {
        this.chatService = chatService;
    }

	@PostMapping("chat")
    public String chat(@RequestBody ChatRequest request, HttpServletRequest httpRequest) {
        var headers = httpRequest.getHeaderNames();
		return chatService.processChat(request.prompt());
    }

    public record ChatRequest(String prompt) {}
}
