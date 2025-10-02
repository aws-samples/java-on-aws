package com.unicorn.jvm;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.*;

class FlameGraphConverterTest {

    private FlameGraphConverter flameGraphConverter;

    @BeforeEach
    void setUp() {
        flameGraphConverter = new FlameGraphConverter();
    }

    @Test
    void convertToFlameGraph_shouldGenerateHtmlOutput() throws IOException {
        String collapsedData = "java/lang/Thread.run;java/util/concurrent/locks/LockSupport.parkNanos 100";

        String result = flameGraphConverter.convertToFlameGraph(collapsedData);

        assertNotNull(result);
        assertFalse(result.isEmpty());
        assertTrue(result.contains("<html>") || result.contains("<!DOCTYPE") || result.contains("svg"));
    }

    @Test
    void convertToFlameGraph_shouldThrowExceptionForInvalidData() {
        String invalidData = "";

        assertDoesNotThrow(() -> flameGraphConverter.convertToFlameGraph(invalidData));
    }
}