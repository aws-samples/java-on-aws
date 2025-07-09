package com.example.assistant.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.bedrockruntime.model.ServiceQuotaExceededException;
import software.amazon.awssdk.services.bedrockruntime.model.ThrottlingException;

import java.util.function.Supplier;

/**
 * Utility class for handling retries and AWS throttling-related exceptions.
 */
public class RetryUtils {
    private static final Logger logger = LoggerFactory.getLogger(RetryUtils.class);

    /**
     * Execute an operation with automatic retry on throttling exceptions
     * @param operation the operation to execute
     * @return the result of the operation
     */
    public static <T> T executeWithRetry(Supplier<T> operation) {
        int maxRetries = 3;
        long retryDelayMs = 1000; // 1 second

        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                return operation.get();
            } catch (Exception e) {
                boolean isThrottling = isAwsThrottlingRelated(e);

                if (isThrottling && attempt < maxRetries) {
                    logger.warn("Throttling detected on attempt {}/{}, retrying in {}ms: {}",
                              attempt, maxRetries, retryDelayMs, e.getMessage());

                    try {
                        Thread.sleep(retryDelayMs);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        logger.warn("Retry delay interrupted");
                        throw new RuntimeException("Retry interrupted", ie);
                    }

                    // Exponential backoff: increase delay for next retry
                    retryDelayMs *= 2;
                    continue;
                }

                // If not throttling or max retries reached, rethrow the exception
                throw e;
            }
        }

        // This should never be reached, but just in case
        throw new RuntimeException("Maximum retry attempts exceeded");
    }

    /**
     * Utility method to check if an exception or any of its causes is AWS throttling-related
     */
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

    // Private constructor to prevent instantiation
    private RetryUtils() {
        throw new AssertionError("Utility class should not be instantiated");
    }
}
