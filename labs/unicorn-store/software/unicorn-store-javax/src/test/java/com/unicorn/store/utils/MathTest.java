package com.unicorn.store.utils;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class MathTest {

    private final Math math = new Math();

    @Test
    void testWrapperValues() {
        // Test boolean wrapper
        assertEquals(true, math.bool);

        // Test byte wrapper
        assertEquals((byte)1, math.b);

        // Test character wrapper
        assertEquals('c', math.c);

        // Test double wrapper
        assertEquals(1.0, math.d);

        // Test float wrapper
        assertEquals(1.1f, math.f);

        // Test long wrapper
        assertEquals(1L, math.l);

        // Test short wrappers
        assertEquals((short)12, math.sh);
        assertEquals((short)3, math.s3);
        assertEquals((short)3, math.sh3);

        // Test integer wrapper
        assertEquals(1, math.i);
    }

    @Test
    void testDivide() {
        math.divide();
        // Note: Since divide() method is void and doesn't return a value,
        // we can only verify it doesn't throw an exception.
    }
}