package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

/**
 * Spring AI @Tool: query Pyroscope for ranked leaf functions by self-time
 * for a service in a time window, on a specific profile type.
 *
 * Profile types this platform pushes:
 *   - {@link #PROFILE_TYPE_CPU}   — on-CPU samples only (real compute)
 *   - {@link #PROFILE_TYPE_WALL}  — wall-clock samples (running + waiting)
 *
 * Both come from a single async-profiler session per JVM (the collector starts
 * it with {@code -e cpu --wall 10ms}). The collector pushes the resulting JFR
 * once per cycle; Pyroscope's JFR ingester splits it into the two profile
 * types automatically.
 *
 * Top-level @Component because it has two callers:
 *   1. AnalysisService — pre-fetches canonical slices for the prompt, calling
 *      both profile types side by side so the model sees what is hot in
 *      each lens.
 *   2. The model — invoked via tool-calling for additional slices on
 *      different time windows or with narrower label selectors.
 */
@Component
public class PyroscopeTool {

    private static final Logger logger = LoggerFactory.getLogger(PyroscopeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    public static final String PROFILE_TYPE_CPU =
        "process_cpu:cpu:nanoseconds:cpu:nanoseconds";
    public static final String PROFILE_TYPE_WALL =
        "wall:wall:nanoseconds:wall:nanoseconds";

    private final RestClient restClient;
    private final String pyroscopeUrl;

    public PyroscopeTool(@Value("${PYROSCOPE_URL:http://pyroscope.monitoring:4040}") String pyroscopeUrl) {
        this.pyroscopeUrl = pyroscopeUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.pyroscopeUrl).build();
    }

    @Tool(description = """
        Query Pyroscope for the top-N hottest functions by self-time for a
        service in a time window, on a specific profile type. Returns a
        Markdown table ranked by self-time share. Use this to look at specific
        time windows or specific label selectors when the pre-fetched tables
        aren't enough.
        Parameters:
          service     - service name (perf-profile/service label value, with
                        the platform suffix; e.g. unicorn-store-spring-eks).
          profileType - 'cpu' for on-CPU samples only (real compute), or
                        'wall' for wall-clock samples (running + waiting).
                        Use 'cpu' to find what is actually computing; use
                        'wall' to find what is waiting on locks or I/O.
          fromIso     - ISO-8601 start, e.g. 2026-05-09T14:20:00Z
          toIso       - ISO-8601 end
          limit       - max functions to return (default 20 if <=0)
        """)
    public String topFunctions(String service, String profileType,
                               String fromIso, String toIso, int limit) {
        var n = limit <= 0 ? 20 : Math.min(limit, 100);
        var pt = resolveProfileType(profileType);
        try {
            var query = pt + "{service_name=\"" + service + "\"}";
            var from = Instant.parse(fromIso);
            var to = Instant.parse(toIso);
            var url = renderUrl(query, from.toEpochMilli(), to.toEpochMilli());
            var response = restClient.get()
                .uri(java.net.URI.create(url))
                .retrieve()
                .body(String.class);
            return formatTopN(response, n, service, profileLabel(pt), from, to);
        } catch (Exception e) {
            logger.warn("Pyroscope topFunctions failed service={} profileType={} window=[{}..{}]: {}",
                service, profileType, fromIso, toIso, e.getMessage());
            return "Pyroscope query failed: " + e.getMessage();
        }
    }

    // --- helpers ---

    /** Map free-form profile type strings to the canonical Pyroscope ID. */
    private static String resolveProfileType(String input) {
        if (input == null || input.isBlank()) return PROFILE_TYPE_WALL;
        var v = input.trim().toLowerCase();
        return switch (v) {
            case "cpu", "process_cpu", PROFILE_TYPE_CPU -> PROFILE_TYPE_CPU;
            case "wall", "wallclock", "wall-clock", PROFILE_TYPE_WALL -> PROFILE_TYPE_WALL;
            default -> PROFILE_TYPE_WALL;
        };
    }

    /** Short human-readable label for prompt headers. */
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

    private String formatTopN(String renderJson, int n, String service, String profileLabel,
                              Instant from, Instant to) throws Exception {
        var root = MAPPER.readTree(renderJson);
        var names = root.path("flamebearer").path("names");
        var levels = root.path("flamebearer").path("levels");
        var numTicks = root.path("flamebearer").path("numTicks").asLong(0);
        if (numTicks <= 0 || !names.isArray() || !levels.isArray()) {
            return "Pyroscope returned no samples for service=" + service
                + " profile=" + profileLabel
                + " window=[" + from + ".." + to + "]. No data or label mismatch.";
        }
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
        var ranked = selfByName.entrySet().stream()
            .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
            .limit(n)
            .toList();
        var sb = new StringBuilder();
        sb.append("### Pyroscope top-%d (service=%s, profile=%s, %s .. %s)\n\n"
            .formatted(n, service, profileLabel, from, to));
        sb.append("| Rank | Self% | Function |\n");
        sb.append("|------|-------|----------|\n");
        for (int i = 0; i < ranked.size(); i++) {
            var e = ranked.get(i);
            var pct = (100.0 * e.getValue()) / numTicks;
            sb.append("| %d | %.1f | `%s` |\n".formatted(i + 1, pct, e.getKey()));
        }
        return sb.toString();
    }
}
