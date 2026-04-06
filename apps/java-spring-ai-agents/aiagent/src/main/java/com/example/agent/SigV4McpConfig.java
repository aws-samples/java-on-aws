package com.example.agent;

import java.io.ByteArrayInputStream;
import java.util.Set;

import io.modelcontextprotocol.client.transport.customizer.McpSyncHttpClientRequestCustomizer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.http.ContentStreamProvider;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.http.SdkHttpRequest;
import software.amazon.awssdk.http.auth.aws.signer.AwsV4HttpSigner;
import software.amazon.awssdk.http.auth.spi.signer.SignedRequest;
import software.amazon.awssdk.regions.providers.DefaultAwsRegionProviderChain;

// Deactivated in favor to OAuthMcpConfig, because policy can evaluate only JWT principle
@Configuration
public class SigV4McpConfig {

//    private static final Logger log = LoggerFactory.getLogger(SigV4McpConfig.class);
//    private static final Set<String> RESTRICTED_HEADERS = Set.of("content-length", "host", "expect");
//
//    @Bean
//    McpSyncHttpClientRequestCustomizer sigV4RequestCustomizer() {
//        var signer = AwsV4HttpSigner.create();
//        var credentialsProvider = DefaultCredentialsProvider.builder().build();
//        var region = new DefaultAwsRegionProviderChain().getRegion();
//        log.info("SigV4 MCP request customizer: region={}, service=bedrock-agentcore", region);
//
//        return (builder, method, endpoint, body, context) -> {
//            var httpRequest = SdkHttpRequest.builder()
//                .uri(endpoint)
//                .method(SdkHttpMethod.valueOf(method))
//                .putHeader("Content-Type", "application/json")
//                .build();
//
//            ContentStreamProvider payload = (body != null && !body.isEmpty())
//                ? ContentStreamProvider.fromUtf8String(body)
//                : null;
//
//            SignedRequest signedRequest = signer.sign(r -> r
//                .identity(credentialsProvider.resolveIdentity().join())
//                .request(httpRequest)
//                .payload(payload)
//                .putProperty(AwsV4HttpSigner.SERVICE_SIGNING_NAME, "bedrock-agentcore")
//                .putProperty(AwsV4HttpSigner.REGION_NAME, region.id()));
//
//            signedRequest.request().headers().forEach((name, values) -> {
//                if (!RESTRICTED_HEADERS.contains(name.toLowerCase())) {
//                    values.forEach(value -> builder.setHeader(name, value));
//                }
//            });
//        };
//    }
}
