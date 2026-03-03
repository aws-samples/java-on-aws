package com.example.agent;

import org.junit.jupiter.api.Test;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springframework.http.HttpHeaders;

import java.util.Base64;

import static org.junit.jupiter.api.Assertions.*;

class ConversationIdResolverTest {

    @Test
    void resolve_withJwtAndSessionHeader_returnsUserIdColonSessionId() {
        String payload = "{\"sub\":\"user-123\",\"auth_time\":1234567890}";
        String jwt = "header." + Base64.getUrlEncoder().encodeToString(payload.getBytes()) + ".signature";

        HttpHeaders headers = new HttpHeaders();
        headers.add(AgentCoreHeaders.AUTHORIZATION, "Bearer " + jwt);
        headers.add(AgentCoreHeaders.SESSION_ID, "session-abc");
        AgentCoreContext context = new AgentCoreContext(headers);

        String result = ConversationIdResolver.resolve(context);

        assertEquals("user-123:session-abc", result);
    }

    @Test
    void resolve_withSessionHeaderOnly_returnsSessionId() {
        HttpHeaders headers = new HttpHeaders();
        headers.add(AgentCoreHeaders.SESSION_ID, "session-xyz");
        AgentCoreContext context = new AgentCoreContext(headers);

        String result = ConversationIdResolver.resolve(context);

        assertEquals("session-xyz", result);
    }

    @Test
    void resolve_withNoHeaders_returnsGeneratedUuid() {
        HttpHeaders headers = new HttpHeaders();
        AgentCoreContext context = new AgentCoreContext(headers);

        String result = ConversationIdResolver.resolve(context);

        assertNotNull(result);
        assertDoesNotThrow(() -> java.util.UUID.fromString(result));
    }

    @Test
    void resolve_withInvalidJwt_returnsSessionIdOnly() {
        HttpHeaders headers = new HttpHeaders();
        headers.add(AgentCoreHeaders.AUTHORIZATION, "Bearer invalid-jwt");
        headers.add(AgentCoreHeaders.SESSION_ID, "session-fallback");
        AgentCoreContext context = new AgentCoreContext(headers);

        String result = ConversationIdResolver.resolve(context);

        assertEquals("session-fallback", result);
    }

    @Test
    void resolve_withNonBearerAuth_returnsSessionIdOnly() {
        HttpHeaders headers = new HttpHeaders();
        headers.add(AgentCoreHeaders.AUTHORIZATION, "Basic sometoken");
        headers.add(AgentCoreHeaders.SESSION_ID, "session-123");
        AgentCoreContext context = new AgentCoreContext(headers);

        String result = ConversationIdResolver.resolve(context);

        assertEquals("session-123", result);
    }
}
