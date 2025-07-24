package com.example.assistant.util;

import io.github.resilience4j.retry.Retry;
import io.github.resilience4j.retry.RetryConfig;
import io.github.resilience4j.retry.RetryRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.services.bedrockruntime.model.ServiceQuotaExceededException;
import software.amazon.awssdk.services.bedrockruntime.model.ThrottlingException;

import java.time.Duration;

/**
 * Chat Retry configuration for Resilience4J
 */
@Configuration
public class ChatRetryConfig {
    private static final Logger logger = LoggerFactory.getLogger(ChatRetryConfig.class);

    @Value("${assistant.retry.max-attempts:3}")
    private int maxAttempts;

    @Value("${assistant.retry.wait-duration:1}")
    private int waitDurationSeconds;

    @Bean
    public Retry chatRetry() {
        RetryConfig config = RetryConfig.custom()
                .maxAttempts(maxAttempts)
                .waitDuration(Duration.ofSeconds(waitDurationSeconds))
                .retryOnException(throwable -> {
                    logger.warn("Evaluating exception for retry: " + throwable.getMessage(), throwable);
                    return isAwsThrottlingRelated(throwable);
                })
                .build();

        RetryRegistry registry = RetryRegistry.of(config);
        return registry.retry("chatRetry");
    }

    public static boolean isAwsThrottlingRelated(Throwable throwable) {
        Throwable cause = throwable;
        while (cause != null) {
            if (cause instanceof ThrottlingException ||
                    cause instanceof ServiceQuotaExceededException ||
                    (cause.getMessage() != null &&
                            (cause.getMessage().contains("Too many requests") ||
                                    cause.getMessage().contains("throttling") ||
                                    cause.getMessage().contains("rate limit")))) {
                return true;
            }
            cause = cause.getCause();
        }
        return false;
    }
}
