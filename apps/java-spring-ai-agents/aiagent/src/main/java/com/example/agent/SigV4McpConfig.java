package com.example.agent;

import java.io.ByteArrayInputStream;
import java.util.Set;

import io.modelcontextprotocol.client.transport.customizer.McpSyncHttpClientRequestCustomizer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.signer.Aws4Signer;
import software.amazon.awssdk.auth.signer.params.Aws4SignerParams;
import software.amazon.awssdk.http.SdkHttpFullRequest;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.regions.providers.DefaultAwsRegionProviderChain;

@Configuration
public class SigV4McpConfig {

    private static final Logger log = LoggerFactory.getLogger(SigV4McpConfig.class);
    private static final Set<String> RESTRICTED_HEADERS = Set.of("content-length", "host", "expect");

    @Bean
    McpSyncHttpClientRequestCustomizer sigV4RequestCustomizer() {
        var signer = Aws4Signer.create();
        var credentialsProvider = DefaultCredentialsProvider.create();
        var region = new DefaultAwsRegionProviderChain().getRegion();
        log.info("SigV4 MCP request customizer: region={}, service=bedrock-agentcore", region);

        return (builder, method, endpoint, body, context) -> {
            byte[] bodyBytes = (body != null) ? body.getBytes(java.nio.charset.StandardCharsets.UTF_8) : null;

            var sdkRequestBuilder = SdkHttpFullRequest.builder();
            sdkRequestBuilder.uri(endpoint);
            sdkRequestBuilder.method(SdkHttpMethod.valueOf(method));

            if (bodyBytes != null && bodyBytes.length > 0) {
                sdkRequestBuilder.contentStreamProvider(() -> new ByteArrayInputStream(bodyBytes));
                sdkRequestBuilder.putHeader("Content-Length", String.valueOf(bodyBytes.length));
            }
            sdkRequestBuilder.putHeader("Content-Type", "application/json");

            var signedRequest = signer.sign(sdkRequestBuilder.build(), Aws4SignerParams.builder()
                .signingName("bedrock-agentcore")
                .signingRegion(region)
                .awsCredentials(credentialsProvider.resolveCredentials())
                .build());

            signedRequest.headers().forEach((name, values) -> {
                if (!RESTRICTED_HEADERS.contains(name.toLowerCase())) {
                    values.forEach(value -> builder.setHeader(name, value));
                }
            });
        };
    }
}
