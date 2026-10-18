package com.example.agent;

import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.core.SdkRequest;
import software.amazon.awssdk.core.interceptor.Context;
import software.amazon.awssdk.core.interceptor.ExecutionAttributes;
import software.amazon.awssdk.core.interceptor.ExecutionInterceptor;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeAsyncClient;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.ContentBlock;
import software.amazon.awssdk.services.bedrockruntime.model.ConversationRole;
import software.amazon.awssdk.services.bedrockruntime.model.ConverseRequest;
import software.amazon.awssdk.services.bedrockruntime.model.ConverseStreamRequest;
import software.amazon.awssdk.services.bedrockruntime.model.GuardrailConfiguration;
import software.amazon.awssdk.services.bedrockruntime.model.GuardrailConverseContentBlock;
import software.amazon.awssdk.services.bedrockruntime.model.GuardrailConverseTextBlock;
import software.amazon.awssdk.services.bedrockruntime.model.GuardrailStreamConfiguration;
import software.amazon.awssdk.services.bedrockruntime.model.GuardrailTrace;
import software.amazon.awssdk.services.bedrockruntime.model.Message;

/**
 * Applies the guardrail to every Converse call of the Spring AI Bedrock chat model.
 * Spring AI uses these Bedrock clients when they exist as beans; the interceptor adds the guardrail
 * configuration and wraps the latest user message in a guardContent block, so the guardrail evaluates
 * the new message and every answer, not the whole history.
 */
@Configuration
// >> Active only when `app.guardrail.id` is set (`GUARDRAIL_ID` in `~/environment/.envrc`)
@ConditionalOnExpression("!'${app.guardrail.id:}'.isEmpty()")
// <<
public class GuardrailConfig {

    // >> Spring AI uses these clients for the Converse calls; the interceptor runs before every request
    @Bean
    BedrockRuntimeAsyncClient bedrockRuntimeAsyncClient(GuardrailInterceptor interceptor) {
        return BedrockRuntimeAsyncClient.builder()
            .overrideConfiguration(c -> c.addExecutionInterceptor(interceptor))
            .build();
    }

    @Bean
    BedrockRuntimeClient bedrockRuntimeClient(GuardrailInterceptor interceptor) {
        return BedrockRuntimeClient.builder()
            .overrideConfiguration(c -> c.addExecutionInterceptor(interceptor))
            .build();
    }
    // <<

    @Bean
    GuardrailInterceptor guardrailInterceptor(@Value("${app.guardrail.id}") String id,
                                              @Value("${app.guardrail.version}") String version) {
        return new GuardrailInterceptor(id, version);
    }

    record GuardrailInterceptor(String id, String version) implements ExecutionInterceptor {

        @Override
        public SdkRequest modifyRequest(Context.ModifyRequest context, ExecutionAttributes attributes) {
            // >> Streaming calls get a GuardrailStreamConfiguration; the guardrail checks the answer while it streams
            if (context.request() instanceof ConverseStreamRequest request) {
                return request.toBuilder()
                    .guardrailConfig(GuardrailStreamConfiguration.builder()
                        .guardrailIdentifier(id).guardrailVersion(version).trace(GuardrailTrace.ENABLED).build())
                    .messages(guardLatestUserMessage(request.messages()))
                    .build();
            }
            // <<
            if (context.request() instanceof ConverseRequest request) {
                return request.toBuilder()
                    .guardrailConfig(GuardrailConfiguration.builder()
                        .guardrailIdentifier(id).guardrailVersion(version).trace(GuardrailTrace.ENABLED).build())
                    .messages(guardLatestUserMessage(request.messages()))
                    .build();
            }
            return context.request();
        }

        /** Wrap the text of the latest user message that has text (not only tool results) in guardContent. */
        private static List<Message> guardLatestUserMessage(List<Message> messages) {
            List<Message> result = new ArrayList<>(messages);
            for (int i = result.size() - 1; i >= 0; i--) {
                Message message = result.get(i);
                if (message.role() == ConversationRole.USER && message.content().stream().anyMatch(c -> c.text() != null)) {
                    List<ContentBlock> content = message.content().stream()
                        .map(c -> c.text() == null ? c : ContentBlock.fromGuardContent(GuardrailConverseContentBlock
                            .fromText(GuardrailConverseTextBlock.builder().text(c.text()).build())))
                        .toList();
                    result.set(i, message.toBuilder().content(content).build());
                    break;
                }
            }
            return result;
        }
    }
}
