package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.net.URI;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Shared "recent versions for a service" lookup against Pyroscope.
 *
 * Two callers:
 *   - {@link ProfileRatioExporter} — consumes {@link #recentVersionTotals(String, long)}
 *     to publish the {@code perf_profile_cpu_ratio} gauge.
 *   - {@link AnalysisService} — uses {@link #selectCurrentAndBaseline(String, long)} to
 *     pick the two version labels to feed into the Pyroscope diff lane.
 *
 * The sort rule is a single decision made in one place: the newest version is
 * whichever label has the most recent sample timestamp in the query window;
 * the baseline is the next one down. Change this policy here — every caller
 * inherits the new behaviour.
 *
 * The query uses Pyroscope's {@code /querier.v1.QuerierService/SelectSeries}
 * JSON endpoint, grouped by {@code version}. Same approach as the exporter's
 * original implementation; refactored here so the analyzer can reuse it.
 */
@Component
public class PyroscopeVersionService {

    private static final Logger logger = LoggerFactory.getLogger(PyroscopeVersionService.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** process_cpu profile type — same one the collector uploads. */
    public static final String PROFILE_TYPE = "process_cpu:cpu:nanoseconds:cpu:nanoseconds";

    private final RestClient restClient;
    private final String pyroscopeUrl;

    public PyroscopeVersionService(
            @Value("${PYROSCOPE_URL:http://pyroscope.monitoring:4040}") String pyroscopeUrl) {
        this.pyroscopeUrl = pyroscopeUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.pyroscopeUrl).build();
    }

    /** A version label plus its total self-time and latest sample timestamp in the window. */
    public record VersionTotals(String version, long totalNanos, long latestTimestampMs) {}

    /**
     * List every version label present for a service over the last
     * {@code windowSeconds} seconds, sorted by latest sample timestamp
     * descending. The first entry (if present) is the newest version;
     * the second entry, if present, is the prior / baseline version.
     *
     * Returns empty when the service has no samples in the window.
     */
    public List<VersionTotals> recentVersionTotals(String service, long windowSeconds) {
        try {
            var now = Instant.now();
            var from = now.minus(windowSeconds, ChronoUnit.SECONDS);
            var body = Map.of(
                "start", Long.toString(from.toEpochMilli()),
                "end", Long.toString(now.toEpochMilli()),
                "profileTypeID", PROFILE_TYPE,
                "labelSelector", "{service_name=\"" + service + "\"}",
                "groupBy", List.of("version"),
                "step", Math.max(windowSeconds / 20, 15L)
            );
            var raw = restClient.post()
                .uri(URI.create(pyroscopeUrl + "/querier.v1.QuerierService/SelectSeries"))
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(body)
                .retrieve()
                .body(String.class);
            return parseSeriesByVersion(raw);
        } catch (Exception e) {
            logger.warn("SelectSeries query failed for service={}: {}", service, e.getMessage());
            return List.of();
        }
    }

    /**
     * Resolve the current and baseline version labels for a service. Current
     * is the newest version by latest-sample timestamp; baseline is the next
     * version down. Returns a pair where {@code baseline} may be null if only
     * one version has samples in the window.
     */
    public VersionPair selectCurrentAndBaseline(String service, long windowSeconds) {
        var totals = recentVersionTotals(service, windowSeconds);
        if (totals.isEmpty()) return VersionPair.empty();
        var current = totals.get(0).version();
        var baseline = totals.size() >= 2 ? totals.get(1).version() : null;
        return new VersionPair(current, baseline);
    }

    public record VersionPair(String current, String baseline) {
        public static VersionPair empty() { return new VersionPair(null, null); }
        public boolean hasBaseline() { return current != null && baseline != null; }
    }

    /**
     * List every service_name value currently indexed in Pyroscope. Skips
     * internal Pyroscope/Alloy self-metrics that leak in as {@code monitoring/...}.
     * Same helper the exporter needs for its per-service loop.
     */
    public List<String> listServiceNames() {
        try {
            var body = Map.of("name", "service_name", "matchers", List.of());
            var raw = restClient.post()
                .uri(URI.create(pyroscopeUrl + "/querier.v1.QuerierService/LabelValues"))
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(body)
                .retrieve()
                .body(String.class);
            var node = MAPPER.readTree(raw);
            var names = node.path("names");
            var out = new ArrayList<String>();
            if (names.isArray()) {
                for (var n : names) {
                    var v = n.asText("");
                    if (v.isBlank()) continue;
                    if (v.startsWith("monitoring/")) continue;
                    out.add(v);
                }
            }
            return out;
        } catch (Exception e) {
            logger.warn("LabelValues query failed: {}", e.getMessage());
            return List.of();
        }
    }

    private List<VersionTotals> parseSeriesByVersion(String raw) throws Exception {
        // LinkedHashMap preserves insertion order for deterministic tests.
        var totals = new LinkedHashMap<String, long[]>();   // [totalNanos, latestTs]
        var node = MAPPER.readTree(raw);
        var series = node.path("series");
        if (!series.isArray()) return List.of();
        for (var s : series) {
            String version = null;
            var labels = s.path("labels");
            if (labels.isArray()) {
                for (var l : labels) {
                    if ("version".equals(l.path("name").asText(""))) {
                        version = l.path("value").asText("");
                        break;
                    }
                }
            }
            if (version == null || version.isBlank()) version = "unknown";

            long total = 0;
            long latestTs = 0;
            var points = s.path("points");
            if (points.isArray()) {
                for (var p : points) {
                    total += p.path("value").asLong(0);
                    long ts = parseTs(p.path("timestamp"));
                    if (ts > latestTs) latestTs = ts;
                }
            }
            totals.merge(version, new long[]{total, latestTs}, (a, b) ->
                new long[]{a[0] + b[0], Math.max(a[1], b[1])});
        }
        var list = new ArrayList<VersionTotals>(totals.size());
        totals.forEach((v, arr) -> list.add(new VersionTotals(v, arr[0], arr[1])));
        list.sort((a, b) -> Long.compare(b.latestTimestampMs(), a.latestTimestampMs()));
        return list;
    }

    private static long parseTs(JsonNode tsNode) {
        if (tsNode.isNumber()) return tsNode.asLong();
        try { return Long.parseLong(tsNode.asText("0")); }
        catch (Exception _) { return 0L; }
    }
}
