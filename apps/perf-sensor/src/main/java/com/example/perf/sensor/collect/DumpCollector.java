package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.ThreadFacts;
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
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Reaches the perf-profiler sidecar's {@code /dump} HTTP endpoint (port
 * {@code DUMP_PORT}) via the app pod IP and turns {@code jcmd Thread.dump_to_file}
 * / {@code GC.heap_info} output into summarized typed facts (never the raw dump).
 * No MCP server can reach an in-pod endpoint, so the sensor is the only source.
 * Best-effort: any failure yields null facts.
 */
@Component
public class DumpCollector {

    private static final Logger logger = LoggerFactory.getLogger(DumpCollector.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final int SAMPLE_LIMIT = 5;
    private static final int STACK_DEPTH = 8;

    private static final Pattern BLOCKING_GET =
        Pattern.compile("CompletableFuture\\.(get|join)|Future\\.get");
    private static final String[] POOL_WAIT_MARKERS = {"ConcurrentBag", "getConnection", "HikariPool"};

    /** Heap/runtime facts scraped from GC.heap_info + VM.flags; fields null when not parseable. */
    public record HeapInfo(Double heapUsedMi, Double heapCommittedMi, String gcName) {
        static HeapInfo empty() {
            return new HeapInfo(null, null, null);
        }
    }

    private final RestClient http;
    private final int dumpPort;
    // A stack is "request path" if it runs the app's request package (works for
    // virtual threads / ForkJoin carriers too) or is a Tomcat http-nio worker.
    private final String requestPackage;

    public DumpCollector(@Value("${DUMP_PORT:9100}") int dumpPort,
                         @Value("${REQUEST_PACKAGE:com.unicorn.store}") String requestPackage) {
        this.dumpPort = dumpPort;
        this.requestPackage = requestPackage;
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(10));
        this.http = RestClient.builder().requestFactory(factory).build();
    }

    /** Summarized thread facts from the sidecar, or null if the dump is unavailable. */
    public ThreadFacts threads(String podIP, String podName) {
        var body = get(podIP, "threads");
        if (body == null) {
            return null;
        }
        String ts = Instant.now().toString();
        try {
            return parseThreads(body, podName, ts);
        } catch (Exception e) {
            logger.warn("thread dump parse failed: {}", e.getMessage());
            return new ThreadFacts(podName, ts, 0, Map.of(), 0, 0, 0, List.of(), List.of());
        }
    }

    /** Parse a JSON jcmd thread dump into summarized facts (package-visible for tests). */
    ThreadFacts parseThreads(String body, String podName, String ts) throws Exception {
        var root = MAPPER.readTree(body);
        var containers = root.path("threadDump").path("threadContainers");
        var byState = new LinkedHashMap<String, Integer>();
        var blockingFrames = new LinkedHashMap<String, Integer>();
        var sample = new ArrayList<ThreadFacts.ThreadSample>();
        int total = 0, virtual = 0, blockedGet = 0, poolWaiters = 0;

        for (var container : containers) {
            for (var t : container.path("threads")) {
                total++;
                if (t.path("virtual").asBoolean(false)
                    || t.path("name").asText("").contains("VirtualThread")) {
                    virtual++;
                }
                String state = t.path("state").asText(t.path("threadState").asText(""));
                if (!state.isBlank()) {
                    byState.merge(state, 1, Integer::sum);
                }
                var frames = stackFrames(t.path("stack"));
                String stackText = String.join("\n", frames);
                if (!isRequestPath(stackText)) {
                    continue;
                }
                boolean blocking = BLOCKING_GET.matcher(stackText).find();
                if (blocking) {
                    blockedGet++;
                    frames.stream().filter(f -> BLOCKING_GET.matcher(f).find()).findFirst()
                        .ifPresent(f -> blockingFrames.merge(trim(f), 1, Integer::sum));
                }
                if (containsAny(stackText, POOL_WAIT_MARKERS)) {
                    poolWaiters++;
                }
                if (sample.size() < SAMPLE_LIMIT) {
                    sample.add(new ThreadFacts.ThreadSample(
                        t.path("name").asText(""), state,
                        frames.stream().limit(STACK_DEPTH).map(DumpCollector::trim).toList()));
                }
            }
        }
        var topBlocking = blockingFrames.entrySet().stream()
            .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
            .map(e -> new ThreadFacts.FrameCount(e.getKey(), e.getValue()))
            .toList();
        return new ThreadFacts(podName, ts, total, byState, virtual, blockedGet, poolWaiters,
            topBlocking, sample);
    }

    private static List<String> stackFrames(JsonNode stack) {
        var frames = new ArrayList<String>();
        if (stack.isArray()) {
            for (var f : stack) {
                frames.add(f.asText());
            }
        }
        return frames;
    }

    private boolean isRequestPath(String stack) {
        return stack.contains(requestPackage) || stack.contains("http-nio");
    }

    public HeapInfo heap(String podIP) {
        var body = get(podIP, "heap");
        return body == null ? HeapInfo.empty() : parseHeap(body);
    }

    /** Parse GC.heap_info + VM.flags into heap facts (package-visible for tests). */
    HeapInfo parseHeap(String body) {
        String gc = null;
        if (body.contains("UseSerialGC") || body.toLowerCase().contains("serial")) gc = "SerialGC";
        else if (body.contains("UseG1GC") || body.contains("G1 ")) gc = "G1GC";
        else if (body.contains("UseParallelGC")) gc = "ParallelGC";
        else if (body.contains("UseZGC")) gc = "ZGC";
        // GC.heap_info prints one "total <n>K, used <n>K" per generation/region and
        // has no "committed" keyword for the heap. Committed heap = sum of the
        // per-region totals; used heap = sum of the per-region used. (An explicit
        // "committed <n>K", as Metaspace prints, is added in if present.)
        Double committed = kbToMi(sumMatches(body, "total\\s+(\\d+)K"));
        if (committed == null) {
            committed = kbToMi(sumMatches(body, "committed\\s+(\\d+)K"));
        }
        Double used = kbToMi(sumMatches(body, "\\bused\\s+(\\d+)K"));
        return new HeapInfo(used, committed, gc);
    }

    private String get(String podIP, String kind) {
        if (podIP == null || podIP.isBlank()) {
            return null;
        }
        var url = "http://%s:%d/dump?kind=%s".formatted(podIP, dumpPort, kind);
        try {
            return http.get().uri(URI.create(url)).retrieve().body(String.class);
        } catch (Exception e) {
            logger.warn("/dump kind={} via {} failed: {}", kind, podIP, e.getMessage());
            return null;
        }
    }

    private static String trim(String frame) {
        var f = frame.strip();
        return f.startsWith("at ") ? f.substring(3) : f;
    }

    private static boolean containsAny(String haystack, String[] needles) {
        for (var n : needles) {
            if (haystack.contains(n)) {
                return true;
            }
        }
        return false;
    }

    /** Sum every capture-group-1 numeric match, or null when there are none. */
    private static Double sumMatches(String body, String regex) {
        var m = Pattern.compile(regex).matcher(body);
        double sum = 0;
        boolean any = false;
        while (m.find()) {
            sum += Double.parseDouble(m.group(1));
            any = true;
        }
        return any ? sum : null;
    }

    private static Double kbToMi(Double kb) {
        return kb == null ? null : kb / 1024.0;
    }
}
