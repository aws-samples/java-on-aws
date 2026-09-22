package com.example.perf.sensor.collect;

import io.kubernetes.client.openapi.apis.CoreV1Api;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Reads the app container's log (read-only) for the startup line. Complements the
 * Prometheus {@code application.ready.time} metric with the {@code Started} vs
 * {@code Restored} distinction that verifies a CRaC restore, and is the reliable
 * source when Prometheus has not yet scraped a just-restarted pod. Generic regex —
 * no application name.
 */
@Component
public class LogCollector {

    private static final Logger logger = LoggerFactory.getLogger(LogCollector.class);
    // Spring Boot: "Started <App> in 12.3 seconds"; CRaC restore of an onRefresh checkpoint:
    // "Restored <App> in 0.2 seconds"; CRaC restore of a jcmd checkpoint taken after startup:
    // "Spring-managed lifecycle restart completed (restored JVM running for 61 ms)".
    private static final Pattern STARTED =
        Pattern.compile("(Started|Restored) \\S+ in ([0-9.]+) seconds"
            + "|(restored JVM running for) ([0-9]+) ms");

    /** The last Started/Restored line: {kind, seconds, line}, or null if not found. */
    public record StartupLine(String kind, double seconds, String line) {}

    private final CoreV1Api core;

    public LogCollector(CoreV1Api core) {
        this.core = core;
    }

    /** The last Started/Restored line in a log text, or null. */
    static StartupLine parse(String log) {
        if (log == null || log.isBlank()) {
            return null;
        }
        StartupLine last = null;
        Matcher m = STARTED.matcher(log);
        while (m.find()) {
            int lineStart = log.lastIndexOf('\n', m.start()) + 1;
            int lineEnd = log.indexOf('\n', m.end());
            String line = log.substring(lineStart, lineEnd < 0 ? log.length() : lineEnd).strip();
            last = m.group(1) != null
                ? new StartupLine(m.group(1), Double.parseDouble(m.group(2)), line)
                : new StartupLine("Restored", Integer.parseInt(m.group(4)) / 1000.0, line);
        }
        return last;
    }

    public StartupLine lastStartup(String namespace, String podName, String container) {
        if (podName == null) {
            return null;
        }
        try {
            String log = core.readNamespacedPodLog(podName, namespace)
                .container(container)
                .execute();
            return parse(log);
        } catch (Exception e) {
            logger.warn("pod log read failed ns={} pod={}: {}", namespace, podName, e.getMessage());
            return null;
        }
    }
}
