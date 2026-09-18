package com.example.perf.optimizer;

import com.example.perf.optimizer.catalog.Evaluator;
import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.catalog.FindingStatus;
import com.example.perf.optimizer.collect.FactsCollector;
import com.example.perf.optimizer.explain.Explainer;
import com.example.perf.optimizer.explain.Explanation;
import com.example.perf.optimizer.facts.Facts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * The shared measure/analyze engine behind both the MCP tools and the REST API.
 * Java computes everything here — collect facts, evaluate the catalog, rank
 * findings — with NO LLM call. The explainer (Bedrock) is a separate, opt-in step.
 *
 * <p>Per-service in-process state (no persistence): the FIRST facts seen become
 * the <b>baseline</b>; an accumulating <b>ever-open</b> set records every finding
 * that has been OPEN. So a finding that stops firing after a fix reports RESOLVED
 * with a measured <b>baseline→now</b> delta on <em>every</em> subsequent analyze,
 * not just the first.
 */
@Service
public class OptimizerService {

    private static final Logger logger = LoggerFactory.getLogger(OptimizerService.class);

    private final FactsCollector collector;
    private final Evaluator evaluator;
    private final Explainer explainer;

    private final Map<String, Facts> baselineByService = new ConcurrentHashMap<>();
    private final Map<String, Set<String>> everOpenByService = new ConcurrentHashMap<>();
    private final Map<String, Latest> latestByService = new ConcurrentHashMap<>();

    private record Latest(Facts facts, Map<String, Finding> byId) {}

    /** Facts for a service (measure) — no findings, no LLM. Includes the baseline. */
    public record MeasureResult(String service, int windowMinutes, Facts facts, Facts baseline) {}

    /** Ranked findings for a service (analyze). */
    public record AnalyzeResult(String service, int windowMinutes, Facts facts, Facts baseline, List<Finding> findings) {}

    public OptimizerService(FactsCollector collector, Evaluator evaluator, Explainer explainer) {
        this.collector = collector;
        this.evaluator = evaluator;
        this.explainer = explainer;
    }

    public MeasureResult measure(String service, int windowMinutes) {
        var facts = collector.collect(service, windowMinutes);
        var baseline = baselineByService.putIfAbsent(service, facts);
        return new MeasureResult(service, norm(windowMinutes), facts, baseline == null ? facts : baseline);
    }

    /**
     * Collect facts, evaluate the catalog, rank, and enrich RESOLVED findings with a
     * measured baseline→now delta. Deterministic: the same live state yields the same
     * finding set and computed values.
     */
    public AnalyzeResult analyze(String service, int windowMinutes) {
        var facts = collector.collect(service, windowMinutes);
        baselineByService.putIfAbsent(service, facts);
        var baseline = baselineByService.get(service);
        var everOpen = everOpenByService.getOrDefault(service, Set.of());

        var findings = new ArrayList<>(evaluator.evaluate(facts, everOpen));
        for (int i = 0; i < findings.size(); i++) {
            var f = findings.get(i);
            if (f.status() == FindingStatus.RESOLVED) {
                findings.set(i, withDelta(f, baseline, facts));
            }
        }

        // Accumulate every finding that has been OPEN, so RESOLVED persists across analyses.
        var ever = new LinkedHashSet<>(everOpen);
        findings.stream().filter(Finding::isOpen).map(Finding::id).forEach(ever::add);
        everOpenByService.put(service, ever);
        var byId = findings.stream().collect(Collectors.toMap(Finding::id, x -> x, (a, b) -> a));
        latestByService.put(service, new Latest(facts, byId));

        logger.info("analyze service={} everOpen={} findings={}", service, ever, findings.size());
        return new AnalyzeResult(service, norm(windowMinutes), facts, baseline, List.copyOf(findings));
    }

    /**
     * Explain a single finding (the only LLM path). Runs an analyze first if the
     * service has not been analyzed yet. Returns null if the finding id is unknown.
     * The artifact and computed values are Java-rendered and identical across runs.
     */
    public Explanation explain(String service, String findingId) {
        var finding = latestFinding(service, findingId);
        if (finding == null) {
            analyze(service, 15);
            finding = latestFinding(service, findingId);
        }
        if (finding == null) {
            return null;
        }
        return explainer.explain(service, finding, latestFacts(service));
    }

    public Finding latestFinding(String service, String findingId) {
        var latest = latestByService.get(service);
        return latest == null ? null : latest.byId().get(findingId);
    }

    public Facts latestFacts(String service) {
        var latest = latestByService.get(service);
        return latest == null ? null : latest.facts();
    }

    public Facts baseline(String service) {
        return baselineByService.get(service);
    }

    private static int norm(int windowMinutes) {
        return windowMinutes <= 0 ? 15 : windowMinutes;
    }

    // --- RESOLVED delta (measured baseline→now) ---------------------------------

    private Finding withDelta(Finding f, Facts baseline, Facts now) {
        var delta = new ArrayList<String>();
        switch (f.id()) {
            case "memory-over-provisioned" -> {
                delta.add(line("limits.memory", memLimit(baseline), memLimit(now), "Mi"));
                delta.add(line("working-set peak", peak(baseline), peak(now), "Mi"));
            }
            case "startup-cpu-bound" -> {
                delta.add(line("startup", startup(baseline), startup(now), "s"));
                delta.add("resizePolicy: absent → present (in-place CPU resize)");
                delta.add("restartCount: " + restarts(now) + " (0 = resized without restart)");
            }
            case "startup-checkpointable" -> {
                delta.add(line("startup", startup(baseline), startup(now), "s"));
                delta.add("image: " + tag(baseline) + " → " + tag(now));
                delta.add(line("working-set floor", floor(baseline), floor(now), "Mi"));
            }
            default -> delta.add("detector no longer fires (baseline vs now)");
        }
        return new Finding(f.id(), f.title(), f.severity(), f.status(), f.effort(),
            f.gain(), f.learnMore(), f.evidence(), f.computed(), f.fix(), f.kb(), f.reason(), List.copyOf(delta));
    }

    private static String line(String label, Double a, Double b, String unit) {
        return "%s: %s → %s".formatted(label, fmt(a, unit), fmt(b, unit));
    }

    private static String fmt(Double v, String unit) {
        if (v == null) return "n/a";
        return unit.equals("s") ? "%.2f%s".formatted(v, unit) : "%.0f%s".formatted(v, unit);
    }

    private static Double memLimit(Facts f) { return f.workload() == null ? null : f.workload().memLimitMi(); }
    private static Double peak(Facts f)     { return f.runtime() == null ? null : f.runtime().rssPeakMi(); }
    private static Double floor(Facts f)    { return f.runtime() == null ? null : f.runtime().rssFloorMi(); }
    private static Double startup(Facts f)  { return f.runtime() == null ? null : f.runtime().startupSeconds(); }
    private static Integer restarts(Facts f){ return f.runtime() == null ? null : f.runtime().restarts(); }
    private static String tag(Facts f)      { return f.workload() == null ? "n/a" : f.workload().imageTag(); }
}
