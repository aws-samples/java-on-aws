package com.example.perf.optimizer.collect;

import com.example.perf.optimizer.facts.ThreadFacts;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
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
    private static final ObjectMapper MAPPER = new ObjectMapper();
    static final int DUMP_PORT = 9100;

    private static final Pattern STATE = Pattern.compile("java\\.lang\\.Thread\\.State:\\s*(\\w+)");
    // Blocking Future.get()/join() (the planted defect in publishUnicornEvent).
    private static final Pattern BLOCKING_GET = Pattern.compile("CompletableFuture\\.(get|join)|Future\\.get");
    private static final String[] POOL_WAIT_MARKERS = {"ConcurrentBag", "getConnection", "HikariPool"};

    /** Heap/runtime facts scraped from GC.heap_info; fields null when not parseable. */
    public record HeapInfo(Double heapUsedMi, Double heapCommittedMi, String gcName) {
        static HeapInfo empty() {
            return new HeapInfo(null, null, null);
        }
    }

    private final RestClient http;
    // A stack is "request path" if it runs the app's request package (works for
    // virtual threads / ForkJoin carriers too) or is a Tomcat http-nio worker.
    // Idle infra threads (e.g. the HikariCP keepalive) are NOT request path, so
    // an idle pool wait does not count as contention.
    private final String requestPackage;

    public DumpCollector(@Value("${OPTIMIZER_REQUEST_PACKAGE:com.unicorn.store}") String requestPackage) {
        this.requestPackage = requestPackage;
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
        // JSON dump (Thread.dump_to_file -format=json) enumerates VIRTUAL threads;
        // the text fallback (Thread.print) shows only platform/mounted threads.
        return body.stripLeading().startsWith("{") ? parseJson(body) : parseText(body);
    }

    /** Parse the JSON thread dump: walk every thread's stack (incl. virtual threads). */
    private ThreadFacts parseJson(String body) {
        try {
            var containers = MAPPER.readTree(body).path("threadDump").path("threadContainers");
            var byState = new HashMap<String, Integer>();
            int total = 0, poolWaiters = 0;
            boolean blockingOnRequest = false;
            for (var c : containers) {
                for (var t : c.path("threads")) {
                    total++;
                    var stack = stackText(t.path("stack"));
                    if (!isRequestPath(stack)) {
                        continue;
                    }
                    if (BLOCKING_GET.matcher(stack).find()) {
                        blockingOnRequest = true;
                    }
                    if (containsAny(stack, POOL_WAIT_MARKERS)) {
                        poolWaiters++;
                    }
                }
            }
            byState.put("total", total);
            return new ThreadFacts(byState, poolWaiters, blockingOnRequest);
        } catch (Exception e) {
            logger.warn("thread JSON parse failed: {}", e.getMessage());
            return parseText(body);
        }
    }

    /** Legacy Thread.print text parse (platform threads only). */
    private ThreadFacts parseText(String body) {
        var byState = new HashMap<String, Integer>();
        Matcher m = STATE.matcher(body);
        while (m.find()) {
            byState.merge(m.group(1), 1, Integer::sum);
        }
        boolean blockingOnRequest = false;
        int poolWaiters = 0;
        for (var block : body.split("(?m)^(?=\")")) {
            if (!isRequestPath(block)) {
                continue;
            }
            if (BLOCKING_GET.matcher(block).find()) {
                blockingOnRequest = true;
            }
            if (containsAny(block, POOL_WAIT_MARKERS)
                && (block.contains("WAITING") || block.contains("TIMED_WAITING"))) {
                poolWaiters++;
            }
        }
        return new ThreadFacts(byState, poolWaiters, blockingOnRequest);
    }

    private static String stackText(JsonNode stack) {
        if (!stack.isArray()) {
            return "";
        }
        var sb = new StringBuilder();
        for (var frame : stack) {
            sb.append(frame.asText()).append('\n');
        }
        return sb.toString();
    }

    private boolean isRequestPath(String threadBlock) {
        return threadBlock.contains(requestPackage) || threadBlock.contains("http-nio");
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
