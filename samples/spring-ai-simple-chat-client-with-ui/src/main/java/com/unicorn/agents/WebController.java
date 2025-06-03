package com.unicorn.agents;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class WebController {

    @GetMapping("/")
    public String home() {
        return "redirect:/chat";
    }

    @GetMapping("/chat")
    public String chatPage() {
        return "chat";
    }

    @GetMapping("/stream-chat")
    public String streamChatPage() {
        return "stream-chat";
    }
}
