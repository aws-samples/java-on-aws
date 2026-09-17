package com.example.perf.optimizer.explain;

import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.catalog.Fix;
import com.example.perf.optimizer.facts.Facts;
import com.example.perf.optimizer.facts.WorkloadFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Renders a finding's fix artifact DETERMINISTICALLY in Java — the model never
 * touches it. {@code dockerfile} artifacts are returned verbatim from the bundled
 * golden Dockerfiles (so they are byte-identical to {@code apps/dockerfiles}); the
 * {@code .hbs} manifest/source templates get {@code {{token}}} substitution from the
 * finding's computed values plus current workload facts. This is what makes the
 * explain step reproducible (same computed values 10/10).
 */
@Component
public class TemplateRenderer {

    private static final Logger logger = LoggerFactory.getLogger(TemplateRenderer.class);

    /** Render the artifact for a finding, or a short note when it has no template. */
    public String render(Finding finding, Facts facts) {
        var fix = finding.fix();
        if (fix == null || fix.template() == null) {
            return "(advice only — no artifact; see the evidence and computed values)";
        }
        String template = load(fix.template());
        if (Fix.DOCKERFILE.equals(fix.kind())) {
            return template; // verbatim golden Dockerfile
        }
        return substitute(template, substitutions(finding, facts));
    }

    private Map<String, String> substitutions(Finding finding, Facts facts) {
        var s = new LinkedHashMap<String, String>();
        finding.computed().forEach((k, v) -> s.put(k, String.valueOf(v)));
        WorkloadFacts w = facts == null ? null : facts.workload();
        if (w != null) {
            s.put("deployment", nvl(w.deployment()));
            s.put("namespace", nvl(w.namespace()));
            s.put("container", nvl(w.container()));
            s.put("image", nvl(w.imageTag()));
            s.put("current.requests.cpu", cpu(w.cpuRequestCores()));
            s.put("current.limits.cpu", cpu(w.cpuLimitCores()));
            s.put("current.requests.memory", memMi(w.memRequestMi()));
            s.put("current.limits.memory", memMi(w.memLimitMi()));
        }
        return s;
    }

    private static String substitute(String template, Map<String, String> subs) {
        String out = template;
        for (var e : subs.entrySet()) {
            out = out.replace("{{" + e.getKey() + "}}", e.getValue());
        }
        if (out.contains("{{")) {
            logger.warn("template has unresolved tokens after substitution");
        }
        return out;
    }

    private String load(String resourcePath) {
        try {
            return new ClassPathResource(resourcePath).getContentAsString(StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("Cannot load template " + resourcePath, e);
        }
    }

    private static String nvl(String s) {
        return s == null ? "" : s;
    }

    /** Format cores as a Kubernetes CPU quantity: 0.25 → "250m", 1.0 → "1". */
    static String cpu(Double cores) {
        if (cores == null) return "";
        if (cores < 1.0) return Math.round(cores * 1000) + "m";
        return cores == Math.rint(cores) ? String.valueOf(cores.longValue()) : String.valueOf(cores);
    }

    static String memMi(Double mi) {
        return mi == null ? "" : Math.round(mi) + "Mi";
    }
}
