package com.example.agent;

import java.net.URI;
import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.spec.McpError;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springframework.ai.chat.model.ToolContext;
import org.springframework.ai.mcp.SyncMcpToolCallbackProvider;
import org.springframework.ai.tool.ToolCallback;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.definition.ToolDefinition;
import org.springframework.ai.tool.metadata.ToolMetadata;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The backoffice tools through the JWT Gateway with the user's token, so that the Gateway's policies see the user's
 * claims; the IAM Gateway keeps the other tools. Calls that a policy denies return the denial to the model.
 */
@Component
public class GatewayTools {

    private static final String BACKOFFICE = "backoffice___";

    private final String jwtGatewayUrl;
    // One tool list per user token: the Gateway lists only the tools that the user's policies allow
    private final Map<String, List<ToolCallback>> userTools = new ConcurrentHashMap<>();

    public GatewayTools(@Value("${app.jwt-gateway.url}") String jwtGatewayUrl) {
        this.jwtGatewayUrl = jwtGatewayUrl;
    }

    /** The tools of the IAM Gateway; with the JWT Gateway, without the backoffice tools. */
    public ToolCallbackProvider withoutBackoffice(ToolCallbackProvider iamGatewayTools) {
        // >> With the JWT Gateway, the backoffice tools come from there; the IAM Gateway keeps the other tools
        return () -> Arrays.stream(iamGatewayTools.getToolCallbacks())
            .filter(tool -> jwtGatewayUrl.isEmpty() || !tool.getToolDefinition().name().startsWith(BACKOFFICE))
            .map(DenialAsResult::new)
            .toArray(ToolCallback[]::new);
        // <<
    }

    /** The backoffice tools of the JWT Gateway for the user of this request; none without a Bearer token. */
    public List<ToolCallback> forUser(AgentCoreContext request) {
        String authorization = request.getHeader(AgentCoreHeaders.AUTHORIZATION);
        if (jwtGatewayUrl.isEmpty() || authorization == null || !authorization.startsWith("Bearer ")) {
            return List.of();
        }
        return userTools.computeIfAbsent(authorization, this::listTools);
    }

    private List<ToolCallback> listTools(String authorization) {
        URI url = URI.create(jwtGatewayUrl);
        // >> An MCP client that sends the user's `Authorization` header with every request
        HttpClientStreamableHttpTransport transport = HttpClientStreamableHttpTransport
            .builder(url.getScheme() + "://" + url.getAuthority())
            .endpoint(url.getPath())
            .httpRequestCustomizer((builder, method, endpoint, body, context) -> builder.setHeader("Authorization", authorization))
            .build();
        McpSyncClient client = McpClient.sync(transport).requestTimeout(Duration.ofMinutes(2)).build();
        client.initialize();
        // <<
        // >> The Gateway validates the user's Cognito token and hides the tools that the user's policies forbid
        return Arrays.stream(SyncMcpToolCallbackProvider.builder()
                .mcpClients(client)
                .toolFilter((connection, tool) -> tool.name().startsWith(BACKOFFICE))
                .build()
                .getToolCallbacks())
            .map(DenialAsResult::new)
            .map(ToolCallback.class::cast)
            .toList();
        // <<
    }

    // >> The Gateway denies a call with a JSON-RPC error; the tool result tells the model which policy denied it
    private record DenialAsResult(ToolCallback tool) implements ToolCallback {

        @Override
        public ToolDefinition getToolDefinition() {
            return tool.getToolDefinition();
        }

        @Override
        public ToolMetadata getToolMetadata() {
            return tool.getToolMetadata();
        }

        @Override
        public String call(String input) {
            return call(input, null);
        }

        @Override
        public String call(String input, ToolContext context) {
            try {
                return context == null ? tool.call(input) : tool.call(input, context);
            } catch (McpError e) {
                return "Error: " + e.getMessage();
            }
        }
    }
    // <<
}
