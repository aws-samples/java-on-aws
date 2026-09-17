package com.example.perf.optimizer;

import com.example.perf.optimizer.facts.Frame;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Query Pyroscope for ranked leaf functions by self-time for a service in a
 * time window, on a specific profile type. Copied from perf-analyzer; used here
 * as a plain helper (called by the collectors and the legacy tool), NOT exposed
 * as an MCP tool. Direct Pyroscope query — no collector dependency (fits the
 * sidecar-profiler world).
 */
@Component
public class PyroscopeTool {

    private static final Logger logger = LoggerFactory.getLogger(PyroscopeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    public static final String PROFILE_TYPE_CPU  = "process_cpu:cpu:nanoseconds:cpu:nanoseconds";
    public static final String PROFILE_TYPE_WALL = "wall:wall:nanoseconds:wall:nanoseconds";

    /** Ranked leaf functions (self%) plus the total sample count for the window. */
    public record ProfileData(List<Frame> frames, long numTicks) {
        public boolean hasSamples() {
            return numTicks > 0 && !frames.isEmpty();
        }
    }

    private final RestClient restClient;
    private final String pyroscopeUrl;

    public PyroscopeTool(@Value("${PYROSCOPE_URL:http://pyroscope.monitoring:4040}") String pyroscopeUrl) {
        this.pyroscopeUrl = pyroscopeUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.pyroscopeUrl).build();
    }

    /**
     * Structured ranked leaf functions with self% for a profile type ("cpu"/"wall").
     * Never throws: returns an empty {@link ProfileData} on any failure or no data.
     */
    public ProfileData profile(String service, String profileType, String fromIso, String toIso, int limit) {
        var n = limit <= 0 ? 20 : Math.min(limit, 200);
        var pt = resolveProfileType(profileType);
        try {
            var query = pt + "{service_name=\"" + service + "\"}";
            var from = Instant.parse(fromIso);
            var to = Instant.parse(toIso);
            var response = restClient.get()
                .uri(java.net.URI.create(renderUrl(query, from.toEpochMilli(), to.toEpochMilli())))
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
            var selfByName = selfByName(names, levels);
            var frames = new ArrayList<Frame>();
            selfByName.entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
                .limit(n)
                .forEach(e -> frames.add(new Frame(e.getKey(), (100.0 * e.getValue()) / numTicks)));
            return new ProfileData(frames, numTicks);
        } catch (Exception e) {
            logger.warn("Pyroscope profile failed service={} type={} window=[{}..{}]: {}",
                service, profileType, fromIso, toIso, e.getMessage());
            return new ProfileData(List.of(), 0);
        }
    }

    /** Top-N hottest functions by self-time as a markdown table (evidence/legacy). */
    public String topFunctions(String service, String profileType, String fromIso, String toIso, int limit) {
        var data = profile(service, profileType, fromIso, toIso, limit);
        var label = profileLabel(resolveProfileType(profileType));
        if (!data.hasSamples()) {
            return "Pyroscope returned no samples for service=" + service
                + " profile=" + label + " window=[" + fromIso + ".." + toIso + "]. No data or label mismatch.";
        }
        var sb = new StringBuilder();
        sb.append("### Pyroscope top-%d (service=%s, profile=%s, %s .. %s)\n\n"
            .formatted(data.frames().size(), service, label, fromIso, toIso));
        sb.append("| Rank | Self% | Function |\n|------|-------|----------|\n");
        var frames = data.frames();
        for (int i = 0; i < frames.size(); i++) {
            sb.append("| %d | %.1f | `%s` |\n".formatted(i + 1, frames.get(i).selfPct(), frames.get(i).name()));
        }
        return sb.toString();
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

    private static String resolveProfileType(String input) {
        if (input == null || input.isBlank()) return PROFILE_TYPE_WALL;
        return switch (input.trim().toLowerCase()) {
            case "cpu", "process_cpu", PROFILE_TYPE_CPU -> PROFILE_TYPE_CPU;
            default -> PROFILE_TYPE_WALL;
        };
    }

    private static String profileLabel(String pt) {
        return PROFILE_TYPE_CPU.equals(pt) ? "cpu" : "wall";
    }

    private String renderUrl(String query, long fromMs, long toMs) {
        return pyroscopeUrl + "/pyroscope/render"
            + "?query=" + java.net.URLEncoder.encode(query, java.nio.charset.StandardCharsets.UTF_8)
            + "&from=" + fromMs
            + "&until=" + toMs
            + "&format=json"
            + "&max-nodes=16384";
    }
}
