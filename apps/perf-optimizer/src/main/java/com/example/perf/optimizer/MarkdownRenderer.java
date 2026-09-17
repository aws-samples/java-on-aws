package com.example.perf.optimizer;

import com.example.perf.optimizer.OptimizerService.AnalyzeResult;
import com.example.perf.optimizer.OptimizerService.MeasureResult;
import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.catalog.FindingStatus;
import com.example.perf.optimizer.explain.Explanation;
import com.example.perf.optimizer.facts.Facts;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Renders {@link MeasureResult}/{@link AnalyzeResult} as compact Markdown for the
 * MCP text responses (Claude Code reads these). The REST API returns the same
 * records as JSON instead. Pure formatting — no computation.
 */
@Component
public class MarkdownRenderer {

    public String measure(MeasureResult r) {
        var sb = new StringBuilder();
        sb.append("# measure — `%s` (window %dm)\n\n".formatted(r.service(), r.windowMinutes()));
        var f = r.facts();
        sb.append("## Workload (desired state, K8s)\n");
        if (f.workload() == null) {
            sb.append("_Kubernetes facts unavailable (not in-cluster or RBAC/API error)._\n");
        } else {
            var w = f.workload();
            sb.append(kv("image tag", w.imageTag()));
            sb.append(kv("replicas", w.replicas()));
            sb.append(kv("requests", "cpu %s / memory %s".formatted(cores(w.cpuRequestCores()), mi(w.memRequestMi()))));
            sb.append(kv("limits", "cpu %s / memory %s".formatted(cores(w.cpuLimitCores()), mi(w.memLimitMi()))));
            sb.append(kv("cpu resizePolicy", w.cpuResizePolicy() ? "present" : "absent"));
            sb.append(kv("JAVA_TOOL_OPTIONS", w.javaToolOptions() == null ? "(unset)" : w.javaToolOptions()));
            sb.append(kv("sidecars", w.sidecars().isEmpty() ? "(none)" : String.join(", ", w.sidecars())));
            sb.append(kv("HPA", w.hpaPresent() ? "present (%s)".formatted(w.hpaMetricType()) : "absent"));
        }
        sb.append("\n## Runtime (measured)\n");
        if (f.runtime() == null) {
            sb.append("_Runtime facts unavailable._\n");
        } else {
            var rt = f.runtime();
            sb.append(kv("working-set floor / peak", "%s / %s".formatted(mi(rt.rssFloorMi()), mi(rt.rssPeakMi()))));
            sb.append(kv("heap used / committed", "%s / %s".formatted(mi(rt.heapUsedMi()), mi(rt.heapCommittedMi()))));
            sb.append(kv("GC", rt.gcName()));
            sb.append(kv("effective CPUs", rt.effectiveCpuCount()));
            sb.append(kv("startup", rt.startupSeconds() == null ? "n/a" : "%.2f s".formatted(rt.startupSeconds())));
            sb.append(kv("restarts", rt.restarts()));
        }
        appendProfile(sb, f);
        return sb.toString();
    }

    public String analyze(AnalyzeResult r) {
        var sb = new StringBuilder();
        sb.append("# analyze — `%s` (window %dm)\n\n".formatted(r.service(), r.windowMinutes()));
        sb.append("| # | Finding | Status | Sev | Effort | Gain |\n");
        sb.append("|---|---------|--------|-----|--------|------|\n");
        int i = 1;
        for (var f : r.findings()) {
            sb.append("| %d | %s `%s` | **%s** | %s | %s | %s |\n".formatted(
                i++, f.title(), f.id(), f.status(), f.severity(), f.effort(),
                f.gain() == null ? "" : f.gain()));
        }
        sb.append("\n");
        for (var f : r.findings()) {
            if (f.status() == FindingStatus.OPEN || f.status() == FindingStatus.BLOCKED
                || f.status() == FindingStatus.RESOLVED) {
                appendDetail(sb, f);
            }
        }
        sb.append("_No LLM was used to produce this analysis. "
            + "Call `explain <service> <findingId>` for a rationale + ready-to-apply artifact._\n");
        return sb.toString();
    }

    public String explanation(Explanation e) {
        if (e == null) {
            return "Finding not found. Run `analyze` first, then `explain <service> <findingId>`.";
        }
        var sb = new StringBuilder();
        sb.append("# explain — `%s`\n\n".formatted(e.findingId()));
        sb.append("## Rationale\n%s\n\n".formatted(e.rationale()));
        if (e.evidenceLines() != null && !e.evidenceLines().isEmpty()) {
            sb.append("## Evidence & computed values\n");
            e.evidenceLines().forEach(l -> sb.append("- %s\n".formatted(l)));
            sb.append("\n");
        }
        sb.append("## Artifact (apply verbatim — computed by code)\n```\n%s\n```\n\n".formatted(e.artifact()));
        sb.append("## Apply\n```bash\n%s\n```\n\n".formatted(e.applyCommand()));
        if (e.expectedOutcome() != null && !e.expectedOutcome().isBlank()) {
            sb.append("## Expected outcome\n%s\n\n".formatted(e.expectedOutcome()));
        }
        sb.append("Learn more: %s\n".formatted(e.learnMore()));
        return sb.toString();
    }

    private void appendDetail(StringBuilder sb, Finding f) {
        sb.append("### %s — `%s` (%s)\n".formatted(f.title(), f.id(), f.status()));
        if (f.reason() != null) {
            sb.append("- reason: %s\n".formatted(f.reason()));
        }
        if (f.evidence() != null && !f.evidence().isEmpty()) {
            sb.append("- evidence: %s\n".formatted(String.join("; ", f.evidence())));
        }
        if (f.computed() != null && !f.computed().isEmpty()) {
            sb.append("- computed:\n");
            f.computed().forEach((k, v) -> sb.append("    - %s: %s\n".formatted(k, v)));
        }
        if (f.delta() != null && !f.delta().isEmpty()) {
            sb.append("- delta:\n");
            f.delta().forEach(d -> sb.append("    - %s\n".formatted(d)));
        }
        if (f.fix() != null) {
            sb.append("- fix: %s → %s\n".formatted(f.fix().kind(), String.join(", ", f.fix().files())));
        }
        sb.append("- learn more: %s\n\n".formatted(f.learnMore()));
    }

    private void appendProfile(StringBuilder sb, Facts f) {
        if (f.profile() == null || f.profile().samples() == 0) {
            sb.append("\n## Profile\n_No Pyroscope samples in the window._\n");
            return;
        }
        var p = f.profile();
        sb.append("\n## Profile (%d samples)\n".formatted(p.samples()));
        sb.append(kv("JIT share", pct(p.jitSharePct())));
        sb.append(kv("GC share", pct(p.gcSharePct())));
        sb.append(kv("futex/park wall share", pct(p.futexWallSharePct())));
        sb.append(kv("window", Boolean.TRUE.equals(p.warmupWindow()) ? "JIT warm-up (not steady state)" : "warm / steady state"));
    }

    private static String kv(String k, Object v) {
        return "- %s: %s\n".formatted(k, v == null ? "n/a" : v);
    }

    private static String mi(Double v) {
        return v == null ? "n/a" : "%.0f MiB".formatted(v);
    }

    private static String cores(Double v) {
        if (v == null) return "n/a";
        return v == Math.rint(v) ? String.valueOf(v.longValue()) : String.valueOf(v);
    }

    private static String pct(Double v) {
        return v == null ? "n/a" : "%.1f%%".formatted(v);
    }
}
