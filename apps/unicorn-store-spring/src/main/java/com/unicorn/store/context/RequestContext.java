package com.unicorn.store.context;

/**
 * Thread-safe request context using ThreadLocal.
 * Stores request ID for the duration of each HTTP request.
 */
public final class RequestContext {

    private static final ThreadLocal<String> REQUEST_ID = new ThreadLocal<>();

    private RequestContext() {}

    public static void set(String requestId) {
        REQUEST_ID.set(requestId);
    }

    public static String get() {
        return REQUEST_ID.get();
    }

    public static String getOrDefault(String defaultValue) {
        String value = REQUEST_ID.get();
        return value != null ? value : defaultValue;
    }

    public static void clear() {
        REQUEST_ID.remove();
    }
}
