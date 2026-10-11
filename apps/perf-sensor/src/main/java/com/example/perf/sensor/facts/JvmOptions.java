package com.example.perf.sensor.facts;

import java.util.Arrays;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * The JVM options the sensor exports: tuning flags only ({@code -XX:...}, {@code -Xmx},
 * {@code -Xms}, {@code -Xss}, {@code -Xmn}), the ones that size heap, GC and threads. System
 * properties ({@code -D...}), agents and anything else are left out, because a credential can
 * hide in any of them, also quoted with spaces. An allowlist needs no tokenizer: a token that
 * is not exactly a tuning flag, such as half of a quoted value, is dropped.
 */
public final class JvmOptions {

    private static final Pattern TUNING_FLAG = Pattern.compile(
        "-XX:[+-]?[A-Za-z][A-Za-z0-9_]*(=[A-Za-z0-9_.,:/%+-]*)?|-X(mx|ms|ss|mn)[0-9]+[kKmMgGtT]?");

    private JvmOptions() {}

    /** The tuning flags of {@code options} in their order, space-separated; null for null. */
    public static String tuningFlags(String options) {
        if (options == null) {
            return null;
        }
        return Arrays.stream(options.trim().split("\\s+"))
            .filter(t -> TUNING_FLAG.matcher(t).matches())
            .collect(Collectors.joining(" "));
    }
}
