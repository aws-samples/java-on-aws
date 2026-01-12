package com.unicorn.store.model;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Unicorn Model Tests")
class UnicornTest {

    @Test
    @DisplayName("Should create unicorn with all properties")
    void shouldCreateUnicornWithAllProperties() {
        Unicorn unicorn = new Unicorn();
        unicorn.setId("123");
        unicorn.setName("Sparkle");
        unicorn.setAge("5");
        unicorn.setSize("Medium");
        unicorn.setType("Rainbow");

        assertEquals("123", unicorn.getId());
        assertEquals("Sparkle", unicorn.getName());
        assertEquals("5", unicorn.getAge());
        assertEquals("Medium", unicorn.getSize());
        assertEquals("Rainbow", unicorn.getType());
    }

    @Test
    @DisplayName("Should allow null values")
    void shouldAllowNullValues() {
        Unicorn unicorn = new Unicorn();

        assertNull(unicorn.getId());
        assertNull(unicorn.getName());
        assertNull(unicorn.getAge());
        assertNull(unicorn.getSize());
        assertNull(unicorn.getType());
    }

    @Test
    @DisplayName("Should update unicorn properties")
    void shouldUpdateUnicornProperties() {
        Unicorn unicorn = new Unicorn();
        unicorn.setName("Original");
        assertEquals("Original", unicorn.getName());

        unicorn.setName("Updated");
        assertEquals("Updated", unicorn.getName());
    }
}
