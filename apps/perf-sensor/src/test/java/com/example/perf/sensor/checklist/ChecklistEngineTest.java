package com.example.perf.sensor.checklist;

import com.example.perf.sensor.checklist.ChecklistEngine.Item;
import com.example.perf.sensor.checklist.ChecklistEngine.Verdict;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The shipped rules over facts taken from a real baseline run (5/12) and a final run (12/12).
 * What matters: the verdicts, the evidence cells as the workshop shows them, a missing fact is
 * UNKNOWN (never FAIL), no load makes the load items UNKNOWN, and a broken rule fails at load.
 */
class ChecklistEngineTest {

    private static ChecklistEngine shipped() {
        return new ChecklistEngine(ChecklistEngine.class.getResourceAsStream("/checklist-rules.yaml"));
    }

    /** The baseline: 2 GiB limit, default heap, 1 core requested, a blocking publish. */
    private static Map<String, Object> baseline() {
        var f = new HashMap<String, Object>();
        f.put("workload", new HashMap<>(Map.ofEntries(
            Map.entry("memRequestMi", 2048.0), Map.entry("memLimitMi", 2048.0),
            Map.entry("cpuRequestCores", 1.0), Map.entry("cpuLimitCores", 1.0),
            Map.entry("startupProbe", true), Map.entry("startupBudgetSeconds", 50.0),
            Map.entry("startupInitialDelaySeconds", 0.0), Map.entry("readinessInitialDelaySeconds", 0.0),
            Map.entry("livenessBudgetSeconds", 30.0),
            Map.entry("livenessPath", "/actuator/health/liveness"),
            Map.entry("readinessPath", "/actuator/health/readiness"),
            Map.entry("terminationGracePeriodSeconds", 30.0), Map.entry("preStopSleepSeconds", 10.0))));
        f.put("runtime", new HashMap<>(Map.ofEntries(
            Map.entry("restarts", 0.0), Map.entry("workingSetPeakMi", 454.14),
            Map.entry("maxHeapMi", 512.0), Map.entry("initialHeapMi", 32.0),
            Map.entry("effectiveCpuCount", 1.0), Map.entry("gcName", "SerialGC"),
            Map.entry("cpuSteadyCores", 0.138), Map.entry("cpuThrottledRatio", 0.074),
            Map.entry("startupSeconds", 17.06), Map.entry("latencyMeanMs", 10.39))));
        f.put("jfr", new HashMap<>(Map.of(
            "container", Map.of("effectiveCpuCount", 1.0),
            "gc", Map.of("maxMs", 144.8), "safepointTotalMs", 208.4, "pinned", Map.of("count", 0.0))));
        f.put("window", new HashMap<>(Map.of("requestRatePerSec", 49.6)));
        f.put("threads", new HashMap<>(Map.of("requestThreadsBlockedInFutureGet", 1.0,
            "requestThreadsWaitingForConnection", 2.0, "blockedInsideTransaction", 1.0)));
        return f;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> group(Map<String, Object> f, String name) {
        return (Map<String, Object>) f.get(name);
    }

    private static Item item(List<Item> items, int id) {
        return items.stream().filter(i -> i.id() == id).findFirst().orElseThrow();
    }

    @Test
    void baseline_scoresFiveOfTwelve_withTheEvidenceTheWorkshopShows() {
        var items = shipped().evaluate(baseline());
        assertThat(items).hasSize(12);
        assertThat(ChecklistEngine.score(items)).isEqualTo(5);
        assertThat(items.stream().filter(i -> i.verdict() == Verdict.PASS).map(Item::id)).containsExactly(1, 5, 7, 9, 12);
        assertThat(item(items, 1).evidence()).isEqualTo("request 2048 == limit 2048, restarts 0");
        assertThat(item(items, 2).evidence()).isEqualTo("2048 / peak 454.14 = 4.51× (bar 2.5)");
        assertThat(item(items, 3).evidence()).isEqualTo("maxHeap 512 / limit 2048 = 0.25× (bar 0.50–0.80)");
        assertThat(item(items, 4).evidence()).isEqualTo("initial 32 / max 512 = 0.063 (bar ≥0.50)");
        assertThat(item(items, 5).evidence()).isEqualTo("limit 1 → ceil 1 == effectiveCpuCount 1; GC SerialGC at ≤1 CPU");
        assertThat(item(items, 6).evidence()).isEqualTo("request 1 > roundUp(2.5 × steady 0.138 = 0.345, 50m) = 0.35");
        assertThat(item(items, 8).evidence()).isEqualTo("startup 17.06s > 5s bar");
        assertThat(item(items, 9).evidence())
            .isEqualTo("startupBudget 50s ≥ 2×17.06=34.12s; livenessBudget 30s ≥30 and ≥3×gcMax 144.8ms; liveness ≠ readiness path");
        assertThat(item(items, 10).evidence()).isEqualTo("grace 30s < preStop 10s + 30 = 40s");
        assertThat(item(items, 11).evidence())
            .isEqualTo("blockedInFutureGet 1, waitingForConnection 2, blockedInsideTransaction 1 (holds a DB connection)");
        assertThat(item(items, 12).evidence())
            .isEqualTo("latencyMean 10.39ms ≤ 100ms bar; gc.maxMs 144.8, safepointTotalMs 208.4, pinned 0");
    }

    @Test
    void finalState_scoresTwelve() {
        var f = baseline();
        group(f, "workload").putAll(Map.of("memRequestMi", 512.0, "memLimitMi", 512.0,
            "cpuRequestCores", 0.2, "terminationGracePeriodSeconds", 40.0));
        group(f, "runtime").putAll(Map.of("workingSetPeakMi", 302.28, "maxHeapMi", 384.0, "initialHeapMi", 256.0,
            "cpuSteadyCores", 0.116, "startupSeconds", 0.062, "latencyMeanMs", 3.47));
        f.put("threads", Map.of("requestThreadsBlockedInFutureGet", 0.0,
            "requestThreadsWaitingForConnection", 0.0, "blockedInsideTransaction", 0.0));
        var items = shipped().evaluate(f);
        assertThat(ChecklistEngine.score(items)).isEqualTo(12);
        assertThat(item(items, 6).evidence()).isEqualTo("request 0.2 ≤ roundUp(2.5 × steady 0.116 = 0.29, 50m) = 0.3");
        assertThat(item(items, 10).evidence()).isEqualTo("grace 40s ≥ preStop 10s + 30 = 40s");
        assertThat(item(items, 11).evidence()).isEqualTo("blockedInFutureGet 0, waitingForConnection 0, blockedInsideTransaction 0");
    }

    @Test
    void missingFact_isUnknown_neverFail() {
        var f = baseline();
        group(f, "runtime").remove("cpuSteadyCores");
        f.remove("threads");
        var items = shipped().evaluate(f);
        assertThat(item(items, 6).verdict()).isEqualTo(Verdict.UNKNOWN);
        assertThat(item(items, 6).evidence()).startsWith("no steady-state CPU");
        assertThat(item(items, 11).verdict()).isEqualTo(Verdict.UNKNOWN);
        assertThat(item(items, 11).icon()).isEqualTo("🟡");
    }

    @Test
    void noLoad_makesTheLoadItemsUnknown() {
        var f = baseline();
        f.put("window", Map.of("requestRatePerSec", 0.4));
        var items = shipped().evaluate(f);
        assertThat(items.stream().filter(i -> i.verdict() == Verdict.UNKNOWN).map(Item::id)).containsExactly(2, 6, 7, 11, 12);
        assertThat(item(items, 2).evidence()).isEqualTo("no load in window");
    }

    @Test
    void jvmCountFallsBackToRuntime_andAWrongCollectorFails() {
        var f = baseline();
        f.put("jfr", Map.of());
        group(f, "runtime").put("gcName", "G1GC");
        var five = item(shipped().evaluate(f), 5);
        assertThat(five.verdict()).isEqualTo(Verdict.FAIL);
        assertThat(five.evidence()).isEqualTo("limit 1 → ceil 1 == effectiveCpuCount 1; GC G1GC at ≤1 CPU, want SerialGC");
    }

    @Test
    void markdownAndText_carryTheScoreAndOneRowPerItem() {
        var items = shipped().evaluate(baseline());
        var md = ChecklistEngine.markdown(items);
        assertThat(md).startsWith("Score: 5/12\n\n| | # | Practice | Evidence |\n|---|---|---|---|\n");
        assertThat(md.lines().filter(l -> l.startsWith("| ✅") || l.startsWith("| ❌"))).hasSize(12);
        assertThat(ChecklistEngine.text(items)).contains("❌  2  Limit sized from working set");
    }

    @Test
    void brokenRule_failsAtLoad() {
        var yaml = "items:\n  - id: 1\n    practice: x\n    pass: \"runtime.\"\n    evidence: x\n";
        assertThatThrownBy(() -> new ChecklistEngine(new ByteArrayInputStream(yaml.getBytes(StandardCharsets.UTF_8))))
            .hasMessageContaining("checklist rule 1");
    }

    @Test
    void roundUp_hasNoFloatNoise() {
        assertThat(ChecklistEngine.roundUp(0.3275, 0.05)).isEqualTo(0.35);
        assertThat(ChecklistEngine.roundUp(0.35, 0.05)).isEqualTo(0.35);
        assertThat(ChecklistEngine.roundUp(0.2325, 0.05)).isEqualTo(0.25);
    }
}
