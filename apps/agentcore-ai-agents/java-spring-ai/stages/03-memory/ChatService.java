package com.example.agent;

// >>
import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
// <<
import org.springaicommunity.agentcore.annotation.AgentCoreInvocation;
// >>
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springaicommunity.agentcore.memory.longterm.AgentCoreMemory;
// <<
import org.springframework.ai.chat.client.ChatClient;
// >>
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.memory.ChatMemory;
// <<
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

record ChatRequest(String prompt) {}

@Service
public class ChatService {

    // >>
    private static final Logger logger = LoggerFactory.getLogger(ChatService.class);
    // <<

    private final ChatClient chatClient;

    private static final String SYSTEM_PROMPT = """
        You are the travel and expense assistant of the company. You help employees plan business trips,
        follow the travel and expense policies, and keep track of their trips and expenses.

        Rules:
        - Focus on business travel and expenses.
        - Ask for missing details such as dates, origin, or destination instead of guessing them.
        - Do not invent policy rules; say so when you are not sure.

        Format:
        - Be friendly and concise.
        - Use tables to compare options.
        """;

    // >> `AgentCoreMemory` provides the STM and LTM advisors in one bean
    public ChatService(AgentCoreMemory agentCoreMemory,
        ChatClient.Builder chatClientBuilder) {

        List<Advisor> advisors = new ArrayList<>();

        // Memory (STM + LTM)
        advisors.addAll(agentCoreMemory.advisors);
        logger.info("Memory enabled: {} advisors", agentCoreMemory.advisors.size());

    // <<
        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            // >> Register the advisors with the `ChatClient`
            .defaultAdvisors(advisors.toArray(new Advisor[0]))
            // <<
            .build();
    }

    @AgentCoreInvocation
    // >> The conversation ID comes from the session header
    public Flux<String> chat(ChatRequest request, AgentCoreContext context) {
        return chat(request.prompt(), getConversationId(context));
    }

    private Flux<String> chat(String prompt, String sessionId) {
        return chatClient.prompt().user(prompt)
            .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
            .stream().content();
    }

    private String getConversationId(AgentCoreContext context) {
        return context.getHeader(AgentCoreHeaders.SESSION_ID);
    }
    // <<
}
