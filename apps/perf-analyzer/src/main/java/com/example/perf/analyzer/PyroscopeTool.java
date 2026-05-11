package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Instant;
import java.util.Map;

/**
 * Spring AI @Tool: query Pyroscope for ranked leaf functions by self-time.
 *
 * This is a top-level @Component because it has two callers:
 *   1. AnalysisService — pre-fetches a canonical window for the prompt.
 *   2. The model — invoked via tool-calling for additional slices.
 *
 * Compare GitHubSourceCodeTool, which is a nested class inside AiService
 * because only the model ever calls it and only when GITHUB_REPO_URL is set.
 *
 * Uses Pyroscope's /pyroscope/render endpoint with format=json — stable across
 * Pyroscope releases and gives a flamebearer we walk to produce top-N.
 */
@Component
public class PyroscopeTool {

    private static final Logger logger = LoggerFactory.getLogger(PyroscopeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RestClient restClient;

    public PyroscopeTool(@Value("${PYROSCOPE_URL:http://pyroscope.monitoring:4040}") String pyroscopeUrl) {
        this.restClient = RestClient.builder().baseUrl(pyroscopeUrl).build();
    }

    @Tool(description = """
        Query Pyroscope for the top-N hottest functions by self-time for a
        service in a time window. Returns a Markdown table ranked by self-time
        share. Use this to look at specific time windows or compare a named
        label selector (for example, a specific version label).
        Parameters:
          service  - service name (perf-profile/service label value)
          fromIso  - ISO-8601 start, e.g. 2026-05-09T14:20:00Z
          toIso    - ISO-8601 end
          limit    - max functions to return (default 20 if <=0)
        """)
    public String topFunctions(String service, String fromIso, String toIso, int limit) {
        var n = limit <= 0 ? 20 : Math.min(limit, 100);
        try {
            var query = "process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name=\"%s\"}"
                .formatted(service);
            var from = Instant.parse(fromIso);
            var to = Instant.parse(toIso);
            var response = restClient.get()
                .uri(b -> b
                    .path("/pyroscope/render")
                    .queryParam("query", query)
                    .queryParam("from", Long.toString(from.toEpochMilli()))
                    .queryParam("until", Long.toString(to.toEpochMilli()))
                    .queryParam("format", "json")
                    .queryParam("max-nodes", 16384)
                    .build())
                .retrieve()
                .body(String.class);
            return formatTopN(response, n, service, from, to);
        } catch (Exception e) {
            logger.warn("Pyroscope query failed for service={} window=[{}..{}]: {}",
                service, fromIso, toIso, e.getMessage());
            return "Pyroscope query failed: " + e.getMessage();
        }
    }

    private String formatTopN(String renderJson, int n, String service, Instant from, Instant to)
            throws Exception {
        var root = MAPPER.readTree(renderJson);
        var names = root.path("flamebearer").path("names");
        var levels = root.path("flamebearer").path("levels");
        var numTicks = root.path("flamebearer").path("numTicks").asLong(0);
        if (numTicks <= 0 || !names.isArray() || !levels.isArray()) {
            return "Pyroscope returned no samples for service=" + service
                + " window=[" + from + ".." + to + "]. No data or service label mismatch.";
        }
        var selfByName = new java.util.HashMap<String, Long>();
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
        sb.append("### Pyroscope top-%d (service=%s, %s .. %s)\n\n".formatted(n, service, from, to));
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
