package com.example.agent;

import io.micrometer.context.ContextRegistry;
import io.modelcontextprotocol.client.transport.customizer.McpSyncHttpClientRequestCustomizer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestAttributesThreadLocalAccessor;
import org.springframework.web.context.request.RequestContextHolder;

@Configuration
public class OAuthMcpConfig {
    private static final Logger logger = LoggerFactory.getLogger(OAuthMcpConfig.class);

    static {
        ContextRegistry.getInstance().registerThreadLocalAccessor(new RequestAttributesThreadLocalAccessor());
    }

    @Bean
    McpSyncHttpClientRequestCustomizer oauthRequestCustomizer() {
        logger.info("OAuth token injection configured");

        return (builder, method, endpoint, body, context) -> {
            String auth = getAuthFromRequestContext();
            if (auth != null) {
                logger.info("Authorization header propagated to MCP calls");
                builder.setHeader(HttpHeaders.AUTHORIZATION, auth);
            }
        };
    }

    private String getAuthFromRequestContext() {
        try {
            return (String) RequestContextHolder.currentRequestAttributes()
                    .getAttribute(HttpHeaders.AUTHORIZATION, RequestAttributes.SCOPE_REQUEST);
        } catch (IllegalStateException e) {
            logger.warn("Authorization header cannot be retrieved from local context: " + e.getMessage(), e);
            return null;
        }
    }
}
