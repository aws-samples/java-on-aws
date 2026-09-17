package com.example.perf.optimizer.catalog;

/**
 * Deterministic helper functions callable from catalog SpEL expressions as
 * {@code #roundUpMi(...)} and {@code #pct(...)}. All memory inputs are MiB
 * (facts and computed values alike); Kubernetes quantity strings like
 * {@code "768Mi"} / {@code "1Gi"} are also accepted and normalised to MiB.
 */
public final class SpelHelpers {

    private SpelHelpers() {}

    /**
     * Round a MiB value UP to the next multiple of {@code stepMi} and format it as
     * a Kubernetes memory quantity, e.g. {@code roundUpMi(414.7, 64) == "448Mi"}.
     */
    public static String roundUpMi(Object mi, int stepMi) {
        long v = (long) Math.ceil(toMi(mi));
        long rounded = ((v + stepMi - 1) / stepMi) * stepMi;
        return rounded + "Mi";
    }

    /**
     * Percentage reduction from {@code from} down to {@code to}, rounded to a whole
     * number, e.g. {@code pct(2048, "768Mi") == 63} (a 63% cut). Negative if it grew.
     */
    public static long pct(Object from, Object to) {
        double f = toMi(from);
        double t = toMi(to);
        if (f == 0) {
            return 0;
        }
        return Math.round(100.0 * (f - t) / f);
    }

    /** Coerce a number or a Kubernetes memory quantity string to MiB. */
    static double toMi(Object o) {
        if (o == null) {
            return 0;
        }
        if (o instanceof Number n) {
            return n.doubleValue();
        }
        var s = o.toString().trim();
        try {
            if (s.endsWith("Gi")) {
                return Double.parseDouble(s.substring(0, s.length() - 2)) * 1024.0;
            }
            if (s.endsWith("Mi")) {
                return Double.parseDouble(s.substring(0, s.length() - 2));
            }
            if (s.endsWith("Ki")) {
                return Double.parseDouble(s.substring(0, s.length() - 2)) / 1024.0;
            }
            return Double.parseDouble(s);
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
