package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.Frame;
import com.example.perf.sensor.facts.ProfileFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Query Pyroscope {@code /pyroscope/render} for ranked leaf functions by self-time on a
 * profile type (cpu|wall), and derive the JIT / GC / futex shares the sizing guard and
 * the optimization skill read. Shares are computed in Java over EVERY leaf frame of the
 * flame graph (not only the top-N returned) — deterministic, no LLM. Never throws: any
 * failure yields empty data and dependent facts become null.
 */
@Component
public class PyroscopeClient {

    private static final Logger logger = LoggerFactory.getLogger(PyroscopeClient.class);
    private static final ObjectMapper MAPPER = JsonMapper.builder().build();

    private static final String PROFILE_TYPE_CPU  = "process_cpu:cpu:nanoseconds:cpu:nanoseconds";
    private static final String PROFILE_TYPE_WALL = "wall:wall:nanoseconds:wall:nanoseconds";
    /** Profiler sampling interval as samples per profiled second (the sidecar's AP_INTERVAL=10ms). */
    private static final double SAMPLES_PER_SECOND = 100.0;

    // Leaf-name substrings that identify JIT/C2 compiler, GC, and futex/park frames.
    private static final List<String> JIT = List.of(
        "PhaseChaitin", "PhaseIdealLoop", "PhaseLive", "PhaseCFG", "Compile::", "Compilation::",
        "CodeHeap", "C2Compiler", "C1_", "Compiler::", "OptoRuntime", "Matcher::");
    private static final List<String> GC = List.of(
        "MarkSweep", "PSYoungGen", "PSScavenge", "G1", "GCTaskThread", "GenCollectedHeap",
        "SerialHeap", "CardTable", "VM_GenCollect", "gc/", "TenuredGeneration", "DefNewGeneration");
    // Park / futex leaves. ConcurrentBag is HikariCP's pool wait.
    private static final List<String> FUTEX = List.of(
        "futex", "Unsafe.park", "Unsafe_Park", "park(", "PlatformEvent", "pthread_cond",
        "ConcurrentBag", "Park::");

    /**
     * Ranked leaf functions (self%), the sample count for the window, and the shares over
     * the whole profile (null when the profile is empty).
     */
    public record ProfileData(List<Frame> frames, long samples, Double jitShare, Double gcShare, Double futexShare) {
        public boolean hasSamples() {
            return samples > 0 && !frames.isEmpty();
        }
    }

    private final RestClient restClient;
    private final String pyroscopeUrl;

    public PyroscopeClient(@Value("${PYROSCOPE_URL:http://pyroscope.monitoring:4040}") String pyroscopeUrl) {
        this.pyroscopeUrl = pyroscopeUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.pyroscopeUrl).build();
    }

    /** Ranked leaf functions with self% for a profile type ("cpu"/"wall"), plus whole-profile shares. */
    public ProfileData profile(String service, String profileType, String fromIso, String toIso, int limit) {
        var pt = resolveProfileType(profileType);
        try {
            var query = pt + "{service_name=\"" + service + "\"}";
            var from = Instant.parse(fromIso);
            var to = Instant.parse(toIso);
            var response = restClient.get()
                .uri(URI.create(renderUrl(query, from.toEpochMilli(), to.toEpochMilli())))
                .retrieve()
                .body(String.class);
            return parse(MAPPER.readTree(response), limit);
        } catch (Exception e) {
            logger.warn("Pyroscope profile failed service={} type={} window=[{}..{}]: {}",
                service, profileType, fromIso, toIso, e.getMessage());
            return empty();
        }
    }

    /** Reduce a {@code /pyroscope/render} JSON body to ProfileData (package-visible for tests). */
    static ProfileData parse(JsonNode root, int limit) {
        var n = limit <= 0 ? 15 : Math.min(limit, 200);
        var fb = root.path("flamebearer");
        var names = fb.path("names");
        var levels = fb.path("levels");
        var numTicks = fb.path("numTicks").asLong(0);
        if (numTicks <= 0 || !names.isArray() || !levels.isArray()) {
            return empty();
        }
        // numTicks is in the profile's tick unit; metadata.sampleRate is ticks per second. For
        // JFR-ingested async-profiler data the unit is nanoseconds (sampleRate 1e9), so
        // numTicks / sampleRate is profiled seconds. One sample is one profiler interval; the
        // sidecar's interval is 10 ms, so 100 samples per profiled second. Without a sampleRate
        // the ticks are reported as they are.
        long sampleRate = root.path("metadata").path("sampleRate").asLong(0);
        long samples = sampleRate > 1 ? Math.round(SAMPLES_PER_SECOND * numTicks / sampleRate) : numTicks;
        var selfByName = selfByName(names, levels);
        var frames = new ArrayList<Frame>();
        selfByName.entrySet().stream()
            .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
            .limit(n)
            .forEach(e -> frames.add(new Frame(e.getKey(), round1((100.0 * e.getValue()) / numTicks))));
        return new ProfileData(frames, samples,
            share(selfByName, numTicks, JIT), share(selfByName, numTicks, GC), share(selfByName, numTicks, FUTEX));
    }

    /**
     * CPU + wall profile summary over the window: top frames of each, and the
     * JIT / GC (CPU) and futex (wall) shares. {@code samples} is the CPU sample count.
     */
    public ProfileFacts summarize(String service, String fromIso, String toIso, int topN) {
        var cpu = profile(service, "cpu", fromIso, toIso, topN);
        var wall = profile(service, "wall", fromIso, toIso, topN);
        if (!cpu.hasSamples() && !wall.hasSamples()) {
            return new ProfileFacts(List.of(), List.of(), null, null, null, 0);
        }
        return new ProfileFacts(cpu.frames(), wall.frames(),
            cpu.hasSamples() ? cpu.jitShare() : null,
            cpu.hasSamples() ? cpu.gcShare() : null,
            wall.hasSamples() ? wall.futexShare() : null,
            cpu.samples());
    }

    /** JIT (cpu) / GC (cpu) / futex (wall) share for a single requested type, plus frames. */
    public record TopResult(List<Frame> frames, Double jitShare, Double gcShare, Double futexWallShare, long samples) {}

    public TopResult top(String service, String type, String fromIso, String toIso, int limit) {
        var data = profile(service, type, fromIso, toIso, limit);
        boolean cpu = isCpu(type);
        return new TopResult(data.frames(),
            cpu && data.hasSamples() ? data.jitShare() : null,
            cpu && data.hasSamples() ? data.gcShare() : null,
            !cpu && data.hasSamples() ? data.futexShare() : null,
            data.samples());
    }

    /** Percent of ALL self ticks in frames whose name contains any of the substrings. */
    private static double share(Map<String, Long> selfByName, long numTicks, List<String> needles) {
        long sum = 0;
        for (var e : selfByName.entrySet()) {
            for (var needle : needles) {
                if (e.getKey().contains(needle)) {
                    sum += e.getValue();
                    break;
                }
            }
        }
        return round1(100.0 * sum / numTicks);
    }

    private static Map<String, Long> selfByName(JsonNode names, JsonNode levels) {
        var selfByName = new HashMap<String, Long>();
        for (var level : levels) {
            if (!level.isArray()) continue;
            for (int i = 0; i + 3 < level.size(); i += 4) {
                var self = level.get(i + 2).asLong(0);
                var nameIdx = level.get(i + 3).asInt(-1);
                if (self <= 0 || nameIdx < 0 || nameIdx >= names.size()) continue;
                selfByName.merge(names.get(nameIdx).asText(), self, Long::sum);
            }
        }
        return selfByName;
    }

    private static ProfileData empty() {
        return new ProfileData(List.of(), 0, null, null, null);
    }

    private static boolean isCpu(String input) {
        return input != null && switch (input.trim().toLowerCase()) {
            case "cpu", "process_cpu" -> true;
            default -> false;
        };
    }

    private static String resolveProfileType(String input) {
        return isCpu(input) ? PROFILE_TYPE_CPU : PROFILE_TYPE_WALL;
    }

    private static double round1(double v) {
        return Math.round(v * 10.0) / 10.0;
    }

    private String renderUrl(String query, long fromMs, long toMs) {
        return pyroscopeUrl + "/pyroscope/render"
            + "?query=" + URLEncoder.encode(query, StandardCharsets.UTF_8)
            + "&from=" + fromMs
            + "&until=" + toMs
            + "&format=json"
            + "&max-nodes=16384";
    }
}
