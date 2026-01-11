package com.unicorn.store.context;

// Java 25 Scoped Values (JEP 506) - thread-safe request context without ThreadLocal
// https://openjdk.org/jeps/506
public final class RequestContext {

    public static final ScopedValue<String> REQUEST_ID = ScopedValue.newInstance();

    private RequestContext() {}
}
