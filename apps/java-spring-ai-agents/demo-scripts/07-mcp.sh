#!/bin/bash
set -e

echo "=============================================="
echo "07-mcp.sh - Add MCP Client + SigV4"
echo "=============================================="

cd ~/environment/aiagent

# --- Get GATEWAY_URL from demo-full ---

source ~/demo-full/.envrc 2>/dev/null || true

if [ -z "$GATEWAY_URL" ]; then
    echo "Error: GATEWAY_URL not found in ~/demo-full/.envrc"
    exit 1
fi

# --- Add MCP + SigV4 dependencies to pom.xml ---

if ! grep -q "spring-ai-starter-mcp-client" pom.xml; then
    sed -i '/<artifactId>bedrockruntime<\/artifactId>/,/<\/dependency>/{
        /<\/dependency>/a \
\t\t<!-- MCP Client -->\n\t\t<dependency>\n\t\t\t<groupId>org.springframework.ai</groupId>\n\t\t\t<artifactId>spring-ai-starter-mcp-client</artifactId>\n\t\t</dependency>\n\t\t<!-- AWS SDK SigV4 signing for MCP client -->\n\t\t<dependency>\n\t\t\t<groupId>software.amazon.awssdk</groupId>\n\t\t\t<artifactId>auth</artifactId>\n\t\t</dependency>\n\t\t<dependency>\n\t\t\t<groupId>software.amazon.awssdk</groupId>\n\t\t\t<artifactId>regions</artifactId>\n\t\t</dependency>
    }' pom.xml
fi

# --- Add MCP properties ---

if ! grep -q "spring.ai.mcp.client" src/main/resources/application.properties; then
    cat >> src/main/resources/application.properties << EOF

# MCP Client
spring.ai.mcp.client.toolcallback.enabled=true
spring.ai.mcp.client.initialized=false
spring.ai.mcp.client.streamable-http.connections.gateway.url=${GATEWAY_URL}
EOF
fi

# --- Write SigV4McpConfig.java ---

cat <<'EOF' > src/main/java/com/example/agent/SigV4McpConfig.java
package com.example.agent;

import java.util.Set;

import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.client.transport.customizer.McpSyncHttpClientRequestCustomizer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.mcp.customizer.McpClientCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.http.ContentStreamProvider;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.http.SdkHttpRequest;
import software.amazon.awssdk.http.auth.aws.signer.AwsV4HttpSigner;
import software.amazon.awssdk.http.auth.spi.signer.SignedRequest;
import software.amazon.awssdk.regions.providers.DefaultAwsRegionProviderChain;

@Configuration
public class SigV4McpConfig {

    private static final Logger log = LoggerFactory.getLogger(SigV4McpConfig.class);
    private static final Set<String> RESTRICTED_HEADERS = Set.of("content-length", "host", "expect");

    @Bean
    McpClientCustomizer<HttpClientStreamableHttpTransport.Builder> sigV4RequestCustomizer() {
        var signer = AwsV4HttpSigner.create();
        var credentialsProvider = DefaultCredentialsProvider.builder().build();
        var region = new DefaultAwsRegionProviderChain().getRegion();
        log.info("SigV4 MCP request customizer: region={}, service=bedrock-agentcore", region);

        McpSyncHttpClientRequestCustomizer requestCustomizer = (builder, method, endpoint, body, context) -> {
            var httpRequest = SdkHttpRequest.builder()
                .uri(endpoint)
                .method(SdkHttpMethod.valueOf(method))
                .putHeader("Content-Type", "application/json")
                .build();

            ContentStreamProvider payload = (body != null && !body.isEmpty())
                ? ContentStreamProvider.fromUtf8String(body)
                : null;

            SignedRequest signedRequest = signer.sign(r -> r
                .identity(credentialsProvider.resolveIdentity().join())
                .request(httpRequest)
                .payload(payload)
                .putProperty(AwsV4HttpSigner.SERVICE_SIGNING_NAME, "bedrock-agentcore")
                .putProperty(AwsV4HttpSigner.REGION_NAME, region.id()));

            signedRequest.request().headers().forEach((name, values) -> {
                if (!RESTRICTED_HEADERS.contains(name.toLowerCase())) {
                    values.forEach(value -> builder.setHeader(name, value));
                }
            });
        };

        return (name, transportBuilder) -> {
            transportBuilder.httpRequestCustomizer(requestCustomizer);
        };
    }
}
EOF

# --- Update ChatService.java (patch, don't overwrite) ---

CHATSERVICE=src/main/java/com/example/agent/ChatService.java

# Add imports if missing
if ! grep -q "ToolCallbackProvider" "$CHATSERVICE"; then
    sed -i '/import org.springframework.ai.vectorstore.VectorStore;/a \
import org.springframework.ai.tool.ToolCallbackProvider;\nimport org.springframework.beans.factory.annotation.Qualifier;' "$CHATSERVICE"
fi

# Add mcpTools constructor param (before chatClientBuilder)
if ! grep -q "mcpToolCallbacks" "$CHATSERVICE"; then
    sed -i 's/ChatClient.Builder chatClientBuilder)/@Qualifier("mcpToolCallbacks") ToolCallbackProvider mcpTools,\n                       ChatClient.Builder chatClientBuilder)/' "$CHATSERVICE"

    # If toolCallbackProviders already exists (from browser/code-interpreter), just add MCP wiring
    if grep -q "toolCallbackProviders" "$CHATSERVICE"; then
        sed -i '/this.chatClient = chatClientBuilder/i \
\        // MCP Tools\n        if (mcpTools != null) {\n            toolCallbackProviders.add(mcpTools);\n            logger.info("MCP tools enabled");\n        }\n' "$CHATSERVICE"
    else
        # Add full toolCallbackProviders block + MCP wiring
        sed -i '/this.chatClient = chatClientBuilder/i \
\        // Tool Callback Providers\n        List<ToolCallbackProvider> toolCallbackProviders = new ArrayList<>();\n\n        // MCP Tools\n        if (mcpTools != null) {\n            toolCallbackProviders.add(mcpTools);\n            logger.info("MCP tools enabled");\n        }\n' "$CHATSERVICE"

        # Add .defaultToolCallbacks() to builder
        sed -i 's/\.build();/.defaultToolCallbacks(toolCallbackProviders.toArray(new ToolCallbackProvider[0]))\n            .build();/' "$CHATSERVICE"
    fi
fi

echo ""
echo "MCP added: deps + SigV4McpConfig + properties + ChatService updated"
read -p "Press ENTER to continue..."

git add -A
git commit -q -m "Add MCP client with SigV4 authentication"

cd ~/environment/aiagent && ./mvnw spring-boot:run
