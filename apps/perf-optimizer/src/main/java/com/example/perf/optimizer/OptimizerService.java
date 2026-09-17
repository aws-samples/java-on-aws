package com.example.perf.optimizer;

import com.example.perf.optimizer.catalog.Evaluator;
import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.catalog.FindingStatus;
import com.example.perf.optimizer.collect.FactsCollector;
import com.example.perf.optimizer.facts.Facts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * The shared measure/analyze engine behind both the MCP tools and the REST API.
 * Java computes everything here — collect facts, evaluate the catalog, rank
 * findings — with NO LLM call. The explainer (Bedrock) is a separate, opt-in
 * step (see {@code explain=true} / the {@code explain} tool).
 *
 * <p>A small in-process cache remembers each service's previously-OPEN findings
 * and the facts behind them, so a re-analyze after a fix reports the finding
 * RESOLVED with a measured before→after delta (no persistence needed for the PoC).
 */
@Service
public class OptimizerService {

    private static final Logger logger = LoggerFactory.getLogger(OptimizerService.class);

    private final FactsCollector collector;
    private final Evaluator evaluator;
    private final Map<String, PriorState> priorByService = new ConcurrentHashMap<>();

    private record PriorState(Set<String> openIds, Facts facts, Map<String, Finding> byId) {}

    /** Facts for a service (measure) — no findings, no LLM. */
    public record MeasureResult(String service, int windowMinutes, Facts facts) {}

    /** Ranked findings for a service (analyze) — no LLM unless {@code explanations} is set elsewhere. */
    public record AnalyzeResult(String service, int windowMinutes, Facts facts, List<Finding> findings) {}

    public OptimizerService(FactsCollector collector, Evaluator evaluator) {
        this.collector = collector;
        this.evaluator = evaluator;
    }

    public MeasureResult measure(String service, int windowMinutes) {
        var facts = collector.collect(service, windowMinutes);
        return new MeasureResult(service, windowMinutes <= 0 ? 15 : windowMinutes, facts);
    }

    /**
     * Collect facts, evaluate the catalog, and rank. Deterministic: the same live
     * state yields the same finding set and computed values. Updates the prior-state
     * cache and enriches RESOLVED findings with a measured delta.
     */
    public AnalyzeResult analyze(String service, int windowMinutes) {
        var facts = collector.collect(service, windowMinutes);
        var prior = priorByService.get(service);
        var priorOpen = prior == null ? Set.<String>of() : prior.openIds();

        var findings = new ArrayList<>(evaluator.evaluate(facts, priorOpen));
        // Attach measured before→after deltas to RESOLVED findings.
        for (int i = 0; i < findings.size(); i++) {
            var fnd = findings.get(i);
            if (fnd.status() == FindingStatus.RESOLVED && prior != null) {
                findings.set(i, withDelta(fnd, prior, facts));
            }
        }

        // Remember the new OPEN set + facts for the next analyze.
        var openIds = findings.stream().filter(Finding::isOpen).map(Finding::id).collect(Collectors.toSet());
        var byId = findings.stream().collect(Collectors.toMap(Finding::id, x -> x, (a, b) -> a));
        priorByService.put(service, new PriorState(openIds, facts, byId));

        logger.info("analyze service={} open={} findings={}", service, openIds, findings.size());
        return new AnalyzeResult(service, windowMinutes <= 0 ? 15 : windowMinutes, facts, List.copyOf(findings));
    }

    /** Lookup a single finding from the latest analyze (used by the explainer). */
    public Finding latestFinding(String service, String findingId) {
        var prior = priorByService.get(service);
        return prior == null ? null : prior.byId().get(findingId);
    }

    public Facts latestFacts(String service) {
        var prior = priorByService.get(service);
        return prior == null ? null : prior.facts();
    }

    // --- RESOLVED delta (measured before→after) ---------------------------------

    private Finding withDelta(Finding f, PriorState prior, Facts now) {
        var delta = new ArrayList<String>();
        var before = prior.facts();
        switch (f.id()) {
            case "memory-over-provisioned" -> {
                delta.add(line("limits.memory", memLimit(before), memLimit(now), "Mi"));
                delta.add(line("working-set peak", peak(before), peak(now), "Mi"));
            }
            case "startup-cpu-bound" -> {
                delta.add("resizePolicy: absent → present (in-place CPU resize)");
                delta.add("restartCount: " + restarts(now) + " (0 = resized without restart)");
            }
            case "startup-checkpointable" -> {
                delta.add(line("startup", startup(before), startup(now), "s"));
                delta.add("image: " + tag(before) + " → " + tag(now));
                delta.add(line("working-set floor", floor(before), floor(now), "Mi"));
            }
            default -> delta.add("detector no longer fires");
        }
        return new Finding(f.id(), f.title(), f.severity(), f.status(), f.effort(),
            f.gain(), f.learnMore(), f.evidence(), f.computed(), f.fix(), f.reason(), List.copyOf(delta));
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
