package com.example.backoffice.common;

import java.util.UUID;

public final class BackofficeConstants {

    public static final String USER_PREFIX = "USER#";

    private BackofficeConstants() {}

    public static String generateId() {
        return UUID.randomUUID().toString().substring(0, 8).toUpperCase();
    }
}
