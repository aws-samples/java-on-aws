package com.example.agent;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.ai.bedrock.converse.BedrockProxyChatModel;
import org.springframework.ai.chat.client.ChatClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.regions.providers.DefaultAwsRegionProviderChain;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test that performs a real Amazon Bedrock Converse call through Spring AI's
 * {@link BedrockProxyChatModel}.
 *
 * <p>Double-guarded so it never runs in environments without AWS access:
 * <ul>
 *   <li>Named {@code *IT} so the Maven Failsafe plugin only runs it during {@code mvn verify}
 *       (the integration-test phase), not during {@code mvn test}.</li>
 *   <li>{@link EnabledIfEnvironmentVariable} skips it unless AWS credentials are present in the
 *       environment (e.g. after sourcing the workshop {@code .env}).</li>
 * </ul>
 * Requires Bedrock model access for the configured model in the resolved region.
 */
@EnabledIfEnvironmentVariable(named = "AWS_ACCESS_KEY_ID", matches = ".+")
class BedrockConverseChatIT {

    private static final String MODEL_ID = "global.anthropic.claude-sonnet-4-6";

    private ChatClient newChatClient() {
        Region region = new DefaultAwsRegionProviderChain().getRegion();
        BedrockProxyChatModel model = BedrockProxyChatModel.builder()
                .region(region)
                .build();
        return ChatClient.builder(model).build();
    }

    @Test
    void converse_returnsNonEmptyResponse() {
        String answer = newChatClient().prompt()
                .options(org.springframework.ai.bedrock.converse.BedrockChatOptions.builder()
                        .model(MODEL_ID)
                        .maxTokens(64))
                .user("Reply with exactly the word: PONG")
                .call()
                .content();

        assertThat(answer).isNotBlank();
        assertThat(answer.toUpperCase()).contains("PONG");
    }
}
