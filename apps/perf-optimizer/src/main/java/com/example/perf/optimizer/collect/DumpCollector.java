package com.example.perf.optimizer.collect;

import com.example.perf.optimizer.facts.ThreadFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.net.URI;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Reaches the perf-profiler sidecar's {@code /dump} HTTP endpoint (port 9100) via
 * the app pod IP and turns {@code jcmd Thread.print} / {@code GC.heap_info} output
 * into typed facts. Everything is best-effort: any failure (endpoint absent, old
 * sidecar image, timeout) yields null facts and the dependent findings degrade to
 * NOT_EVALUABLE. Read-only; the optimizer never writes to the cluster.
 */
@Component
public class DumpCollector {

    private static final Logger logger = LoggerFactory.getLogger(DumpCollector.class);
    static final int DUMP_PORT = 9100;

    private static final Pattern STATE = Pattern.compile("java\\.lang\\.Thread\\.State:\\s*(\\w+)");
    // Blocking Future.get()/join() on a request-handling thread.
    private static final Pattern BLOCKING_GET = Pattern.compile("CompletableFuture\\.(get|join)|Future\\.get");
    private static final String[] REQUEST_MARKERS = {"http-nio", "tomcat", "servlet", "unicorn", "DispatcherServlet"};
    private static final String[] POOL_WAIT_MARKERS = {"HikariPool", "ConcurrentBag", "getConnection"};

    /** Heap/runtime facts scraped from GC.heap_info; fields null when not parseable. */
    public record HeapInfo(Double heapUsedMi, Double heapCommittedMi, String gcName) {
        static HeapInfo empty() {
            return new HeapInfo(null, null, null);
        }
    }

    private final RestClient http;

    public DumpCollector() {
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(10));
        this.http = RestClient.builder().requestFactory(factory).build();
    }

    public ThreadFacts threads(String podIP) {
        var body = get(podIP, "threads");
        if (body == null) {
            return null;
        }
        var byState = new HashMap<String, Integer>();
        Matcher m = STATE.matcher(body);
        while (m.find()) {
            byState.merge(m.group(1), 1, Integer::sum);
        }
        boolean blockingOnRequest = false;
        int poolWaiters = 0;
        for (var block : body.split("(?m)^(?=\")")) {
            var lower = block.toLowerCase();
            boolean isRequest = containsAny(lower, REQUEST_MARKERS);
            if (isRequest && BLOCKING_GET.matcher(block).find()) {
                blockingOnRequest = true;
            }
            if (containsAny(block, POOL_WAIT_MARKERS)
                && (block.contains("WAITING") || block.contains("TIMED_WAITING"))) {
                poolWaiters++;
            }
        }
        return new ThreadFacts(byState, poolWaiters, blockingOnRequest);
    }

    public HeapInfo heap(String podIP) {
        var body = get(podIP, "heap");
        if (body == null) {
            return HeapInfo.empty();
        }
        String gc = null;
        if (body.contains("UseSerialGC") || body.toLowerCase().contains("serial")) gc = "SerialGC";
        else if (body.contains("UseG1GC") || body.contains("G1 ")) gc = "G1GC";
        else if (body.contains("UseParallelGC")) gc = "ParallelGC";
        else if (body.contains("UseZGC")) gc = "ZGC";
        Double used = kbToMi(firstMatch(body, "used\\s+(\\d+)K"));
        Double committed = kbToMi(firstMatch(body, "committed\\s+(\\d+)K"));
        return new HeapInfo(used, committed, gc);
    }

    private String get(String podIP, String kind) {
        if (podIP == null || podIP.isBlank()) {
            return null;
        }
        var url = "http://%s:%d/dump?kind=%s".formatted(podIP, DUMP_PORT, kind);
        try {
            return http.get().uri(URI.create(url)).retrieve().body(String.class);
        } catch (Exception e) {
            logger.warn("/dump kind={} via {} failed: {}", kind, podIP, e.getMessage());
            return null;
        }
    }

    private static boolean containsAny(String haystack, String[] needles) {
        for (var n : needles) {
            if (haystack.contains(n.toLowerCase()) || haystack.contains(n)) {
                return true;
            }
        }
        return false;
    }

    private static Double firstMatch(String body, String regex) {
        var m = Pattern.compile(regex).matcher(body);
        return m.find() ? Double.parseDouble(m.group(1)) : null;
    }

    private static Double kbToMi(Double kb) {
        return kb == null ? null : kb / 1024.0;
    }
}
