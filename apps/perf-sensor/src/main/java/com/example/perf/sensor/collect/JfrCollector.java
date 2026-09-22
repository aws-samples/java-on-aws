package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.JfrFacts;
import com.example.perf.sensor.facts.JfrFacts.Compilation;
import com.example.perf.sensor.facts.JfrFacts.ContainerConfig;
import com.example.perf.sensor.facts.JfrFacts.FrameCount;
import com.example.perf.sensor.facts.JfrFacts.GcPauses;
import com.example.perf.sensor.facts.JfrFacts.MonitorWait;
import com.example.perf.sensor.facts.JfrFacts.Pinned;
import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordedFrame;
import jdk.jfr.consumer.RecordedStackTrace;
import jdk.jfr.consumer.RecordingFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Fetches the app JVM's JFR ring through the profiler sidecar ({@code /dump?kind=jfr}) and
 * reduces it to {@link JfrFacts} with the JDK's own {@code jdk.jfr.consumer}. Read-only,
 * best-effort: null when the sidecar or the recording is unavailable. The ring is the
 * retrospective source for what the JVM itself saw: container limits, its arguments, GC
 * pauses, pinning, contention, safepoints, JIT volume. It does NOT carry virtual-thread
 * parks (JFR emits jdk.ThreadPark only for platform threads), so request-path blocking
 * stays a live thread-dump concern.
 */
@Component
public class JfrCollector {

    private static final Logger logger = LoggerFactory.getLogger(JfrCollector.class);
    private static final int TOP = 5;
    private static final int STACK_SCAN_DEPTH = 64;

    private final RestClient http;
    private final int dumpPort;
    private final String requestPackage;

    public JfrCollector(@Value("${DUMP_PORT:9100}") int dumpPort,
                        @Value("${REQUEST_PACKAGE:com.unicorn.store}") String requestPackage) {
        this.dumpPort = dumpPort;
        this.requestPackage = requestPackage;
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(60));
        this.http = RestClient.builder().requestFactory(factory).build();
    }

    /** Dump + parse the ring of the given pod, or null when unavailable. */
    public JfrFacts collect(String podIP, String podName) {
        if (podIP == null || podIP.isBlank()) {
            return null;
        }
        var url = "http://%s:%d/dump?kind=jfr".formatted(podIP, dumpPort);
        Path tmp = null;
        try {
            byte[] bytes = http.get().uri(URI.create(url)).retrieve().body(byte[].class);
            if (bytes == null || bytes.length == 0) {
                return null;
            }
            tmp = Files.createTempFile("perf-ring-", ".jfr");
            Files.write(tmp, bytes);
            return parse(tmp, podName);
        } catch (Exception e) {
            logger.warn("JFR ring via {} failed: {}", podIP, e.getMessage());
            return null;
        } finally {
            if (tmp != null) {
                try {
                    Files.deleteIfExists(tmp);
                } catch (IOException ignored) {
                    // temp cleanup only
                }
            }
        }
    }

    /** Reduce a JFR file to facts (package-visible for tests). */
    JfrFacts parse(Path file, String podName) throws IOException {
        Instant first = null, last = null;
        ContainerConfig container = null;
        String jvmArgs = null;
        int gcCount = 0;
        double gcMax = 0, gcTotal = 0;
        String gcLongest = null;
        int pinCount = 0;
        double pinMax = 0;
        var pinFrames = new LinkedHashMap<String, Integer>();
        var monitors = new LinkedHashMap<String, double[]>();   // class -> {count, totalMs}
        var monitorFrames = new LinkedHashMap<String, LinkedHashMap<String, Integer>>();   // class -> frame -> count
        double safepointTotal = 0;
        boolean anySafepoint = false;
        int compCount = 0;
        double compTotal = 0, compMax = 0;

        try (var recording = new RecordingFile(file)) {
            while (recording.hasMoreEvents()) {
                RecordedEvent e = recording.readEvent();
                Instant t = e.getStartTime();
                if (t != null) {
                    if (first == null || t.isBefore(first)) first = t;
                    if (last == null || t.isAfter(last)) last = t;
                }
                switch (e.getEventType().getName()) {
                    case "jdk.ContainerConfiguration" -> container = new ContainerConfig(
                        (int) e.getLong("effectiveCpuCount"),
                        quotaCores(e),
                        e.getLong("memoryLimit") > 0 ? e.getLong("memoryLimit") / (1024.0 * 1024.0) : null,
                        e.getString("containerType"));
                    case "jdk.JVMInformation" -> {
                        // null when the JVM was started without -XX flags: keep "" so the caller can tell
                        // "event seen, no args" from "ring unavailable" (null).
                        String a = e.getString("jvmArguments");
                        jvmArgs = a == null ? "" : a;
                    }
                    case "jdk.GCPhasePause" -> {
                        double ms = millis(e.getDuration());
                        gcCount++;
                        gcTotal += ms;
                        if (ms > gcMax) {
                            gcMax = ms;
                            gcLongest = e.getString("name");
                        }
                    }
                    case "jdk.VirtualThreadPinned" -> {
                        pinCount++;
                        pinMax = Math.max(pinMax, millis(e.getDuration()));
                        var frames = frames(e.getStackTrace());
                        frames.stream().filter(f -> f.startsWith(requestPackage)).findFirst()
                            .or(() -> frames.stream().findFirst())
                            .ifPresent(f -> pinFrames.merge(f, 1, Integer::sum));
                    }
                    case "jdk.JavaMonitorEnter" -> {
                        String cls = e.getClass("monitorClass") == null ? "?" : e.getClass("monitorClass").getName();
                        var acc = monitors.computeIfAbsent(cls, k -> new double[2]);
                        acc[0]++;
                        acc[1] += millis(e.getDuration());
                        // The monitor class alone ("java.lang.Object", "[I") names nothing; the waiting
                        // thread's frame does. Prefer the first app frame, else the top frame.
                        var frames = frames(e.getStackTrace());
                        frames.stream().filter(f -> f.startsWith(requestPackage)).findFirst()
                            .or(() -> frames.stream().findFirst())
                            .ifPresent(f -> monitorFrames.computeIfAbsent(cls, k -> new LinkedHashMap<>())
                                .merge(f, 1, Integer::sum));
                    }
                    case "jdk.SafepointBegin" -> {
                        anySafepoint = true;
                        safepointTotal += millis(e.getDuration());
                    }
                    case "jdk.Compilation" -> {
                        double ms = millis(e.getDuration());
                        compCount++;
                        compTotal += ms;
                        compMax = Math.max(compMax, ms);
                    }
                    default -> { }
                }
            }
        }

        var monitorTop = monitors.entrySet().stream()
            .sorted(Comparator.comparingDouble((Map.Entry<String, double[]> en) -> en.getValue()[1]).reversed())
            .limit(TOP)
            .map(en -> new MonitorWait(en.getKey(), (int) en.getValue()[0], round(en.getValue()[1]),
                monitorFrames.getOrDefault(en.getKey(), new LinkedHashMap<>()).entrySet().stream()
                    .max(Map.Entry.comparingByValue()).map(Map.Entry::getKey).orElse(null)))
            .toList();

        return new JfrFacts(podName,
            first == null ? null : first.toString(),
            last == null ? null : last.toString(),
            container, jvmArgs,
            gcCount == 0 ? new GcPauses(0, null, null, null) : new GcPauses(gcCount, round(gcMax), round(gcTotal), gcLongest),
            new Pinned(pinCount, pinCount == 0 ? null : round(pinMax), top(pinFrames)),
            monitorTop,
            anySafepoint ? round(safepointTotal) : null,
            compCount == 0 ? new Compilation(0, null, null) : new Compilation(compCount, round(compTotal), round(compMax)));
    }

    private static List<String> frames(RecordedStackTrace st) {
        var out = new ArrayList<String>();
        if (st == null) return out;
        for (RecordedFrame f : st.getFrames()) {
            if (out.size() >= STACK_SCAN_DEPTH) break;
            var m = f.getMethod();
            if (m == null || m.getType() == null) continue;
            out.add(m.getType().getName() + "." + m.getName()
                + (f.getLineNumber() > 0 ? ":" + f.getLineNumber() : ""));
        }
        return out;
    }

    private static List<FrameCount> top(Map<String, Integer> counts) {
        return counts.entrySet().stream()
            .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
            .limit(TOP)
            .map(en -> new FrameCount(en.getKey(), en.getValue()))
            .toList();
    }

    private static Double quotaCores(RecordedEvent e) {
        long quota = e.getLong("cpuQuota");
        long period = e.getLong("cpuSlicePeriod");
        return quota > 0 && period > 0 ? quota / (double) period : null;
    }

    private static double millis(Duration d) {
        return d == null ? 0 : d.toNanos() / 1_000_000.0;
    }

    private static Double round(double v) {
        return Math.round(v * 10.0) / 10.0;
    }
}
