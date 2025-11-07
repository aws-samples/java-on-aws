package com.example.ai.agent.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.ui.Model;
import org.springframework.beans.factory.annotation.Value;

@Controller
public class WebViewController {

    @Value("${ui.features.multi-user:true}")
    private boolean multiUserEnabled;

    @Value("${ui.features.multi-modal:true}")
    private boolean multiModalEnabled;

    @GetMapping("/")
    public String index(Model model) {
        model.addAttribute("multiUserEnabled", multiUserEnabled);
        model.addAttribute("multiModalEnabled", multiModalEnabled);
        return "chat";
    }
}
