package com.example.ai.agent.controller;

import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.annotation.RegisteredOAuth2AuthorizedClient;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class WebViewController {
    @GetMapping("/")
    public String index(@RegisteredOAuth2AuthorizedClient("authserver") OAuth2AuthorizedClient authorizedClient) {
        authorizedClient.getAccessToken();
        return "chat";
    }
}
