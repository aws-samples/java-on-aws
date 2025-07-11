package com.example.backoffice.common;

import java.security.SecureRandom;

/**
 * Utility class for generating reference codes used across the application.
 * Centralizes reference generation to avoid code duplication.
 */
public final class ReferenceGenerator {
    private static final String CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    private static final SecureRandom RANDOM = new SecureRandom();

    private ReferenceGenerator() {
        // Utility class, no instantiation
    }

    /**
     * Generates a random alphanumeric reference code of specified length
     *
     * @param length The length of the reference code to generate
     * @return A random alphanumeric string
     */
    public static String generate(int length) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < length; i++) {
            sb.append(CHARS.charAt(RANDOM.nextInt(CHARS.length())));
        }
        return sb.toString();
    }

    /**
     * Generates a reference code with a prefix and specified length
     *
     * @param prefix The prefix to add to the reference code
     * @param length The length of the random part of the reference code
     * @return A prefixed reference code
     */
    public static String generateWithPrefix(String prefix, int length) {
        return prefix + "-" + generate(length);
    }
}
