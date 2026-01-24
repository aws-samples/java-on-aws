package com.example.agent;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

@RestController
@CrossOrigin(origins = "*")
@ConditionalOnProperty(name = "app.controller.enabled", havingValue = "true", matchIfMissing = true)
public class InvocationController {
    private final ChatService chatService;

    public InvocationController(ChatService chatService) {
        this.chatService = chatService;
    }

    @PostMapping(value = "invocations", produces = MediaType.TEXT_PLAIN_VALUE)
    public Flux<String> handleInvocation(
            @RequestBody InvocationRequest request,
            @RequestParam(required = false, defaultValue = "default") String username) {
        return chatService.chat(request.prompt(), username);
    }
}