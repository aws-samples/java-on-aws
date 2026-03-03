package com.example.agent;

import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.Base64;
import java.util.UUID;

/**
 * Utility for extracting conversation ID from AgentCore context.
 * Format: userId:sessionId (authenticated) or sessionId (anonymous)
 */
public final class ConversationIdResolver {

    private static final Logger logger = LoggerFactory.getLogger(ConversationIdResolver.class);
    private static final JsonMapper jsonMapper = JsonMapper.builder().build();

    private ConversationIdResolver() {}

    public static String resolve(AgentCoreContext context) {
        String sessionId = context.getHeader(AgentCoreHeaders.SESSION_ID);
        if (sessionId == null || sessionId.isBlank()) {
            sessionId = UUID.randomUUID().toString();
        }

        String authHeader = context.getHeader(AgentCoreHeaders.AUTHORIZATION);
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            try {
                String jwt = authHeader.substring(7);
                String payload = new String(Base64.getUrlDecoder().decode(jwt.split("\\.")[1]));
                JsonNode claims = jsonMapper.readTree(payload);
                String userId = claims.get("sub").asString();
                return userId + ":" + sessionId;
            } catch (Exception e) {
                logger.debug("JWT parsing failed, using sessionId only", e);
            }
        }

        return sessionId;
    }
}
