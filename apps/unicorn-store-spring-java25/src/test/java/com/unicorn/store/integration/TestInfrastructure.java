package com.unicorn.store.integration;

import org.junit.jupiter.api.extension.ExtendWith;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

// Unified test infrastructure - provides PostgreSQL (Testcontainers) or H2 fallback
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@ExtendWith(TestInfrastructureInitializer.class)
public @interface TestInfrastructure {
}
