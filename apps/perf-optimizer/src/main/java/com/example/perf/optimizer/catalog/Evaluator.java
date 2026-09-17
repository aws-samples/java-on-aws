package com.example.perf.optimizer.catalog;

import com.example.perf.optimizer.facts.Facts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.expression.MapAccessor;
import org.springframework.expression.Expression;
import org.springframework.expression.spel.standard.SpelExpressionParser;
import org.springframework.expression.spel.support.StandardEvaluationContext;
import org.springframework.stereotype.Component;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Pure catalog evaluator: {@code Facts -> List<Finding>}. No I/O, no LLM — every
 * value is computed here from measured facts, so repeated runs on the same facts
 * are byte-for-byte identical. SpEL drives {@code detector}/{@code compute}/
 * {@code gain}; {@code requires} gates on null facts (NOT_EVALUABLE); guard rules
 * gate dependents (BLOCKED); a detector that stops firing after being OPEN
 * becomes RESOLVED.
 */
@Component
public class Evaluator {

    private static final Logger logger = LoggerFactory.getLogger(Evaluator.class);
    private static final SpelExpressionParser PARSER = new SpelExpressionParser();

    private static final Comparator<Finding> RANK = Comparator
        .comparingInt((Finding f) -> f.status().ordinal())
        .thenComparingInt(f -> -f.severity().rank())
        .thenComparingInt(f -> f.effort().rank())
        .thenComparing(Finding::id);

    private final Catalog catalog;

    public Evaluator(Catalog catalog) {
        this.catalog = catalog;
    }

    public List<Finding> evaluate(Facts facts) {
        return evaluate(facts, Set.of());
    }

    /**
     * @param priorOpenIds ids that were OPEN in a previous analyze of the same
     *                     service; a now-false detector for one of these becomes RESOLVED.
     */
    public List<Finding> evaluate(Facts facts, Set<String> priorOpenIds) {
        var ctx = facts.toContext();
        var ec = context(ctx);

        // Pass 1: guard satisfaction (null = could not evaluate).
        var guardSatisfied = new LinkedHashMap<String, Boolean>();
        for (var e : catalog.entries()) {
            if (e.guard()) {
                guardSatisfied.put(e.id(), missing(facts, e).isEmpty() ? evalBool(e.detector(), ec) : null);
            }
        }

        // Pass 2: findings.
        var findings = new ArrayList<Finding>(catalog.entries().size());
        for (var e : catalog.entries()) {
            findings.add(evalEntry(e, facts, ctx, ec, guardSatisfied, priorOpenIds));
        }
        findings.sort(RANK);
        return List.copyOf(findings);
    }

    private Finding evalEntry(CatalogEntry e, Facts facts, Map<String, Object> ctx,
                              StandardEvaluationContext ec, Map<String, Boolean> guards,
                              Set<String> priorOpenIds) {
        var missing = missing(facts, e);
        if (!missing.isEmpty()) {
            return finding(e, FindingStatus.NOT_EVALUABLE, "missing measured facts: " + missing,
                List.of(), Map.of(), null, null);
        }
        Boolean fired = evalBool(e.detector(), ec);
        if (fired == null) {
            return finding(e, FindingStatus.NOT_EVALUABLE, "detector could not be evaluated",
                List.of(), Map.of(), null, null);
        }

        if (e.guard()) {
            // A guard fires-true when its precondition HOLDS (window is warm). Then there
            // is nothing to advise. Fires-false -> surface the advice as OPEN.
            return fired
                ? finding(e, FindingStatus.NOT_APPLICABLE, null, List.of(), Map.of(), null, null)
                : finding(e, FindingStatus.OPEN, e.reason(), renderEvidence(e.evidence(), ctx), Map.of(), null, null);
        }

        if (fired) {
            for (var pre : e.prereqs()) {
                var sat = guards.get(pre);
                if (sat == null || !sat) {
                    var reason = guardReason(pre, sat);
                    return finding(e, FindingStatus.BLOCKED, reason,
                        renderEvidence(e.evidence(), ctx), Map.of(), null, null);
                }
            }
            var computed = compute(e, ec);
            ctx.put("computed", computed);
            var gain = e.gain() == null ? null : evalString(e.gain(), ec);
            return finding(e, FindingStatus.OPEN, null, renderEvidence(e.evidence(), ctx), computed, gain, null);
        }

        // Detector no longer fires.
        if (priorOpenIds.contains(e.id())) {
            return finding(e, FindingStatus.RESOLVED, "detector no longer fires",
                renderEvidence(e.evidence(), ctx), Map.of(), null, null);
        }
        return finding(e, FindingStatus.NOT_APPLICABLE, null, List.of(), Map.of(), null, null);
    }

    private String guardReason(String guardId, Boolean sat) {
        var g = catalog.entries().stream().filter(x -> x.id().equals(guardId)).findFirst().orElse(null);
        if (g != null && g.reason() != null) {
            return g.reason();
        }
        return sat == null
            ? "prerequisite '" + guardId + "' could not be evaluated"
            : "prerequisite '" + guardId + "' not met";
    }

    private static Finding finding(CatalogEntry e, FindingStatus status, String reason,
                                   List<String> evidence, Map<String, Object> computed,
                                   String gain, List<String> delta) {
        return new Finding(e.id(), e.title(), e.severity(), status, e.effort(),
            gain, e.learnMore(), evidence, computed, e.fix(), reason, delta);
    }

    private static List<String> missing(Facts facts, CatalogEntry e) {
        var out = new ArrayList<String>();
        for (var p : e.requires()) {
            if (facts.resolve(p) == null) {
                out.add(p);
            }
        }
        return out;
    }

    private Map<String, Object> compute(CatalogEntry e, StandardEvaluationContext ec) {
        var out = new LinkedHashMap<String, Object>();
        for (var entry : e.compute().entrySet()) {
            try {
                out.put(entry.getKey(), PARSER.parseExpression(entry.getValue()).getValue(ec, Object.class));
            } catch (Exception ex) {
                logger.warn("compute {} [{}] failed: {}", e.id(), entry.getKey(), ex.getMessage());
            }
        }
        return out;
    }

    private static Boolean evalBool(String spel, StandardEvaluationContext ec) {
        try {
            return PARSER.parseExpression(spel).getValue(ec, Boolean.class);
        } catch (Exception ex) {
            logger.warn("detector [{}] failed: {}", spel, ex.getMessage());
            return null;
        }
    }

    private static String evalString(String spel, StandardEvaluationContext ec) {
        try {
            return PARSER.parseExpression(spel).getValue(ec, String.class);
        } catch (Exception ex) {
            return null;
        }
    }

    private static StandardEvaluationContext context(Map<String, Object> root) {
        var ec = new StandardEvaluationContext(root);
        ec.addPropertyAccessor(new MapAccessor());
        try {
            Method roundUp = SpelHelpers.class.getMethod("roundUpMi", Object.class, int.class);
            Method pct = SpelHelpers.class.getMethod("pct", Object.class, Object.class);
            ec.registerFunction("roundUpMi", roundUp);
            ec.registerFunction("pct", pct);
        } catch (NoSuchMethodException ex) {
            throw new IllegalStateException("SpEL helpers missing", ex);
        }
        return ec;
    }

    /** Render measured fact paths as human evidence lines, with units. */
    private static List<String> renderEvidence(List<String> paths, Map<String, Object> ctx) {
        var out = new ArrayList<String>(paths.size());
        for (var p : paths) {
            var v = Facts.resolve(ctx, p);
            out.add(p + " = " + fmt(p, v));
        }
        return out;
    }

    static String fmt(String path, Object v) {
        if (v == null) {
            return "n/a";
        }
        if (v instanceof Number n) {
            if (path.startsWith("rss.") || path.startsWith("heap.")
                || path.endsWith(".memory")) {
                return "%.0f MiB".formatted(n.doubleValue());
            }
            if (path.equals("startup")) {
                return "%.2f s".formatted(n.doubleValue());
            }
            if (path.equals("uptime")) {
                return "%.0f s".formatted(n.doubleValue());
            }
            if (path.startsWith("cpu.") || path.endsWith(".cpu")) {
                return path.equals("cpu.effective")
                    ? String.valueOf(n.intValue())
                    : "%s vCPU".formatted(trimNumber(n.doubleValue()));
            }
            if (path.startsWith("profile.")) {
                return "%.1f%%".formatted(n.doubleValue());
            }
            return trimNumber(n.doubleValue());
        }
        return v.toString();
    }

    private static String trimNumber(double d) {
        return d == Math.rint(d) ? String.valueOf((long) d) : String.valueOf(d);
    }
}
