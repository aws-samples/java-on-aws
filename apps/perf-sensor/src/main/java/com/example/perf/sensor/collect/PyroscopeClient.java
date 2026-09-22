package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.Frame;
import com.example.perf.sensor.facts.ProfileFacts;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Query Pyroscope {@code /pyroscope/render} for ranked leaf functions by
 * self-time on a profile type (cpu|wall), and derive the JIT / GC / futex shares
 * the sizing guard and the optimization skill read. Shares are computed in Java
 * from leaf self-times — deterministic, no LLM. Never throws: any failure yields
 * empty data and dependent facts become null.
 */
@Component
public class PyroscopeClient {

    private static final Logger logger = LoggerFactory.getLogger(PyroscopeClient.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final String PROFILE_TYPE_CPU  = "process_cpu:cpu:nanoseconds:cpu:nanoseconds";
    private static final String PROFILE_TYPE_WALL = "wall:wall:nanoseconds:wall:nanoseconds";

    // Leaf-name substrings that identify JIT/C2 compiler, GC, and futex/park frames.
    private static final List<String> JIT = List.of(
        "PhaseChaitin", "PhaseIdealLoop", "PhaseLive", "PhaseCFG", "Compile::", "Compilation::",
        "CodeHeap", "C2Compiler", "C1_", "Compiler::", "OptoRuntime", "Matcher::");
    private static final List<String> GC = List.of(
        "MarkSweep", "PSYoungGen", "PSScavenge", "G1", "GCTaskThread", "GenCollectedHeap",
        "SerialHeap", "CardTable", "VM_GenCollect", "gc/", "TenuredGeneration", "DefNewGeneration");
    private static final List<String> FUTEX = List.of(
        "futex", "Unsafe.park", "Unsafe_Park", "park(", "PlatformEvent", "pthread_cond",
        "ConcurrentBag", "Park::");

    /** Ranked leaf functions (self%) plus the total sample count for the window. */
    public record ProfileData(List<Frame> frames, long samples) {
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

    /** Ranked leaf functions with self% for a profile type ("cpu"/"wall"). */
    public ProfileData profile(String service, String profileType, String fromIso, String toIso, int limit) {
        var n = limit <= 0 ? 15 : Math.min(limit, 200);
        var pt = resolveProfileType(profileType);
        try {
            var query = pt + "{service_name=\"" + service + "\"}";
            var from = Instant.parse(fromIso);
            var to = Instant.parse(toIso);
            var response = restClient.get()
                .uri(URI.create(renderUrl(query, from.toEpochMilli(), to.toEpochMilli())))
                .retrieve()
                .body(String.class);
            var root = MAPPER.readTree(response);
            var fb = root.path("flamebearer");
            var names = fb.path("names");
            var levels = fb.path("levels");
            var numTicks = fb.path("numTicks").asLong(0);
            if (numTicks <= 0 || !names.isArray() || !levels.isArray()) {
                return new ProfileData(List.of(), 0);
            }
            // numTicks is in the profile's tick unit. For JFR-ingested async-profiler data the
            // unit is time (metadata.sampleRate = ticks per second, 1e9 for nanoseconds), so
            // numTicks / sampleRate is profiled seconds; at the profiler's 10 ms interval that is
            // 100 samples per second. Report sample COUNTS, not nanoseconds.
            long sampleRate = root.path("metadata").path("sampleRate").asLong(0);
            long samples = sampleRate > 1 ? Math.round(100.0 * numTicks / sampleRate) : numTicks;
            var selfByName = selfByName(names, levels);
            var frames = new ArrayList<Frame>();
            selfByName.entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
                .limit(n)
                .forEach(e -> frames.add(new Frame(e.getKey(), round1((100.0 * e.getValue()) / numTicks))));
            return new ProfileData(frames, samples);
        } catch (Exception e) {
            logger.warn("Pyroscope profile failed service={} type={} window=[{}..{}]: {}",
                service, profileType, fromIso, toIso, e.getMessage());
            return new ProfileData(List.of(), 0);
        }
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
        Double jit = cpu.hasSamples() ? share(cpu.frames(), JIT) : null;
        Double gc = cpu.hasSamples() ? share(cpu.frames(), GC) : null;
        Double futex = wall.hasSamples() ? share(wall.frames(), FUTEX) : null;
        return new ProfileFacts(cpu.frames(), wall.frames(), jit, gc, futex, cpu.samples());
    }

    /** JIT (cpu) / GC (cpu) / futex (wall) share for a single requested type, plus frames. */
    public record TopResult(List<Frame> frames, Double jitShare, Double gcShare, Double futexWallShare, long samples) {}

    public TopResult top(String service, String type, String fromIso, String toIso, int limit) {
        var data = profile(service, type, fromIso, toIso, limit);
        boolean cpu = isCpu(type);
        Double jit = cpu && data.hasSamples() ? share(data.frames(), JIT) : null;
        Double gc = cpu && data.hasSamples() ? share(data.frames(), GC) : null;
        Double futex = !cpu && data.hasSamples() ? share(data.frames(), FUTEX) : null;
        return new TopResult(data.frames(), jit, gc, futex, data.samples());
    }

    /** Sum of self% over frames whose name contains any of the substrings. */
    private static double share(List<Frame> frames, List<String> needles) {
        double sum = 0;
        for (var f : frames) {
            for (var needle : needles) {
                if (f.name().contains(needle)) {
                    sum += f.selfPct();
                    break;
                }
            }
        }
        return round1(sum);
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
