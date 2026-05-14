package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Instant;
import java.util.Comparator;
import java.util.HashMap;
import java.util.Map;

/**
 * Spring AI @Tool: query Pyroscope for ranked leaf functions by self-time
 * and for per-frame self-time deltas between two versions of a service.
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
 *   2. The model — invoked via tool-calling for additional slices or diffs.
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
        time windows or specific label selectors (for example, a specific
        version label).
        Parameters:
          service     - service name (perf-profile/service label value)
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

    @Tool(description = """
        Return the per-frame total-time delta between two versions of a service
        in the same time window, on a specific profile type. "Total time" for
        a frame is the share of profile time spent in that frame plus all of
        its descendants — so it surfaces both leaf hotspots and the
        application callers that walked through them. Use this to see what
        changed in a regressing version: a frame whose total-time share is
        large in the current version and small or absent in the baseline is
        most likely the cause of the regression. The application caller of a
        new hotspot will appear here even if it does almost no work itself,
        because its descendants do.
        Choose profileType='cpu' to find new CPU-burning code paths;
        choose profileType='wall' to find new contention or I/O waits.
        Parameters:
          service          - service name
          profileType      - 'cpu' or 'wall'
          baselineVersion  - the 'before' version label (e.g. the prior release)
          currentVersion   - the 'after' version label (e.g. the new one)
          fromIso          - ISO-8601 start, same window for both versions
          toIso            - ISO-8601 end
          limit            - max entries to return (default 20 if <=0)
        Returns a Markdown table sorted by |delta| descending. Each version's
        total-time is normalised to that version's own profile (numTicks), so
        the two percentage columns are comparable regardless of how many
        samples each version produced.
        """)
    public String diff(String service, String profileType,
                       String baselineVersion, String currentVersion,
                       String fromIso, String toIso, int limit) {
        var n = limit <= 0 ? 20 : Math.min(limit, 100);
        if (service == null || baselineVersion == null || currentVersion == null
            || baselineVersion.isBlank() || currentVersion.isBlank()) {
            return "Diff unavailable: need a current and a baseline version.";
        }
        var pt = resolveProfileType(profileType);
        try {
            var from = Instant.parse(fromIso);
            var to = Instant.parse(toIso);
            var baseline = totalsForVersion(service, pt, baselineVersion,
                from.toEpochMilli(), to.toEpochMilli());
            var current = totalsForVersion(service, pt, currentVersion,
                from.toEpochMilli(), to.toEpochMilli());
            return formatDelta(service, profileLabel(pt), baselineVersion, currentVersion,
                from, to, baseline, current, n);
        } catch (Exception e) {
            logger.warn("Pyroscope diff failed service={} profileType={} base={} cur={}: {}",
                service, profileType, baselineVersion, currentVersion, e.getMessage());
            return "Pyroscope diff query failed: " + e.getMessage();
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

    /**
     * Per-version totals from a render-JSON response.
     * @param numTicks the total sample count for this version's profile
     * @param totalByName total-time by function name (self + descendants).
     *                   "Total" surfaces application callers whose own self-time
     *                   is near zero but whose descendants do all the work
     *                   (e.g. a method that hits a contended lock — the wait
     *                   shows up in glibc futex calls, not in the caller).
     */
    private record VersionTotals(long numTicks, Map<String, Long> totalByName) {}

    /** total-time by function name plus numTicks, from a render-JSON response. */
    private VersionTotals totalsForVersion(String service, String profileType, String version,
                                           long fromMs, long toMs) throws Exception {
        var query = profileType
            + "{service_name=\"" + service + "\",version=\"" + version + "\"}";
        var raw = restClient.get()
            .uri(java.net.URI.create(renderUrl(query, fromMs, toMs)))
            .retrieve()
            .body(String.class);
        var root = MAPPER.readTree(raw);
        var fb = root.path("flamebearer");
        var numTicks = fb.path("numTicks").asLong(0);
        var names = fb.path("names");
        var levels = fb.path("levels");
        var out = new HashMap<String, Long>();
        if (!names.isArray() || !levels.isArray()) return new VersionTotals(numTicks, out);
        // Flamebearer level entries are quads: [x, total, self, nameIdx].
        // We sum total per name across appearances. For non-recursive frames
        // there is exactly one appearance, which is the case for the
        // application code we care about.
        for (var level : levels) {
            if (!level.isArray()) continue;
            for (int i = 0; i + 3 < level.size(); i += 4) {
                var total = level.get(i + 1).asLong(0);
                var nameIdx = level.get(i + 3).asInt(-1);
                if (total <= 0 || nameIdx < 0 || nameIdx >= names.size()) continue;
                out.merge(names.get(nameIdx).asText(), total, Long::sum);
            }
        }
        return new VersionTotals(numTicks, out);
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

    /**
     * Build the delta table: for every function name in either version,
     * express each version's total-time for that frame as a share of that
     * version's own numTicks, then rank by |current_share − baseline_share|.
     * "Total time" for a frame is its own self-time plus the time of all
     * its descendants. Using total instead of self surfaces application
     * methods whose self-time is near zero but whose descendants do the
     * actual (or contended) work — e.g. a method that calls into a busy
     * lock will appear here even though the wait shows up in glibc, not
     * in the method itself.
     * A positive delta of +30 pp means "in the current version this frame
     * accounts for 30 percentage points more of the profile than it did
     * in the baseline". Sample-count differences between the two versions
     * are normalised away.
     */
    private String formatDelta(String service, String profileLabel,
                               String baselineVersion, String currentVersion,
                               Instant from, Instant to,
                               VersionTotals baseline, VersionTotals current, int n) {
        long currentTicks = current.numTicks();
        long baselineTicks = baseline.numTicks();
        if (currentTicks <= 0 && baselineTicks <= 0) {
            return "Pyroscope returned no samples for either version of " + service
                + " profile=" + profileLabel
                + " in window=[" + from + ".." + to + "].";
        }

        // Union of frame names.
        var allNames = new HashMap<String, long[]>(); // [baseline, current]
        baseline.totalByName().forEach((k, v) -> allNames.computeIfAbsent(k, _ -> new long[2])[0] = v);
        current.totalByName().forEach((k, v) -> allNames.computeIfAbsent(k, _ -> new long[2])[1] = v);

        // Each row carries the per-version share of that version's own numTicks,
        // in percentage points. Delta is the change in the share.
        record DeltaPctRow(String name, long baseline, long current, double basePct, double curPct) {
            double deltaPct() { return curPct - basePct; }
        }

        double bDenom = Math.max(baselineTicks, 1L);
        double cDenom = Math.max(currentTicks, 1L);
        var ranked = allNames.entrySet().stream()
            .map(e -> new DeltaPctRow(
                e.getKey(), e.getValue()[0], e.getValue()[1],
                100.0 * e.getValue()[0] / bDenom,
                100.0 * e.getValue()[1] / cDenom))
            .sorted(Comparator.comparingDouble((DeltaPctRow r) -> Math.abs(r.deltaPct())).reversed())
            .limit(n)
            .toList();

        var sb = new StringBuilder();
        sb.append("### Pyroscope version diff (service=%s, profile=%s, baseline=%s vs current=%s, %s .. %s)\n\n"
            .formatted(service, profileLabel, baselineVersion, currentVersion, from, to));
        sb.append("Ranked by |Δ| of total-time share. \"Total\" means the frame plus all of its descendants, ")
            .append("so application methods that call into contended locks or hot helpers show up here even ")
            .append("if their own self-time is near zero — their descendants do the work. Each version's ")
            .append("total is normalised to that version's own profile, so the two percentage columns are ")
            .append("comparable regardless of how many samples each version produced. Δ is the percentage-point ")
            .append("change: positive = this frame is a larger share of the current version's profile than of ")
            .append("the baseline's.\n\n");
        sb.append("| Rank | Δ pp | Baseline% | Current% | Function |\n");
        sb.append("|------|------|-----------|----------|----------|\n");
        for (int i = 0; i < ranked.size(); i++) {
            var r = ranked.get(i);
            sb.append("| %d | %+.1f | %.1f | %.1f | `%s` |\n"
                .formatted(i + 1, r.deltaPct(), r.basePct(), r.curPct(), r.name()));
        }
        return sb.toString();
    }
}
