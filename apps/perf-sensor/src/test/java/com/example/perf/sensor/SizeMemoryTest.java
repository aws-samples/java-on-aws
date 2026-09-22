package com.example.perf.sensor;

import com.example.perf.sensor.SensorService.SizeParams;
import com.example.perf.sensor.SensorService.SizeResult;
import com.example.perf.sensor.facts.Facts;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * sizeMemory arithmetic + guard over JSON fact fixtures. Pins the acceptance
 * numbers and determinism (identical output across repeated runs). No collectors,
 * no LLM. Uses the SOP policy parameters (the skill owns the numbers).
 */
class SizeMemoryTest {

    private static final ObjectMapper MAPPER = new ObjectMapper()
        .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    // The java-on-eks-optimization SOP policy parameters.
    private static final SizeParams POLICY =
        new SizeParams(1.40, 1.90, 64, 120, 100, 1, 64);

    private final SensorService sensor = new SensorService(null, null, null, null, null, null, null);

    private Facts fixture(String name) throws IOException {
        try (var in = getClass().getResourceAsStream("/fixtures/" + name + ".json")) {
            assertThat(in).as("fixture %s", name).isNotNull();
            return MAPPER.readValue(in, Facts.class);
        }
    }

    @Test
    void baseline_sizesToAcceptanceRange_serialGc() throws IOException {
        // floor 377, peak 517: limits = roundUp(max(723.8, 716.3), 64) = 768; requests == limits.
        var r = sensor.sizeMemory(fixture("baseline"), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.requests().memory()).isEqualTo("768Mi");
        assertThat(r.limits().memory()).isEqualTo("768Mi");
        assertThat(r.maxRamPercentage()).isEqualTo(75);
        assertThat(r.initialRamPercentage()).isEqualTo(50);
        assertThat(r.gc()).isEqualTo("SerialGC");
        assertThat(r.evidence().rssFloorMi()).isEqualTo(377.0);
        assertThat(r.evidence().rssPeakMi()).isEqualTo(517.0);
    }

    @Test
    void rightSized_stillComputesTargets() throws IOException {
        var r = sensor.sizeMemory(fixture("right-sized"), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.requests().memory()).isEqualTo("768Mi");
        assertThat(r.limits().memory()).isEqualTo("768Mi");
        assertThat(r.gc()).isEqualTo("SerialGC");
    }

    @Test
    void crac_sizesSmall_floorSafetyDominates() throws IOException {
        // floor 190, peak 210: limits=roundUp(max(294,361),64)=384; requests == limits.
        var r = sensor.sizeMemory(fixture("crac"), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.requests().memory()).isEqualTo("384Mi");
        assertThat(r.limits().memory()).isEqualTo("384Mi");
        assertThat(r.gc()).isEqualTo("SerialGC");
    }

    @Test
    void warmupWindow_blockedByGuard_lowUptime() throws IOException {
        var r = sensor.sizeMemory(fixture("warmup-window"), POLICY);
        assertThat(r.status()).isEqualTo("BLOCKED");
        assertThat(r.reason()).contains("not warm");
        assertThat(r.requests()).isNull();
        assertThat(r.limits()).isNull();
        // evidence still reported for the operator.
        assertThat(r.evidence().rssFloorMi()).isEqualTo(400.0);
    }

    @Test
    void missingFacts_blocked() {
        var r = sensor.sizeMemory(new Facts(null, null, null, null, null), POLICY);
        assertThat(r.status()).isEqualTo("BLOCKED");
        assertThat(r.reason()).contains("insufficient measurement");
    }

    @Test
    void gcIsG1_whenMoreThanOneCpu() throws IOException {
        // Same facts but > 1 vCPU would flip GC. Verify the rule directly via a crafted fixture.
        var base = fixture("baseline");
        var wl = base.workload();
        var twoCpu = new com.example.perf.sensor.facts.WorkloadFacts(
            wl.namespace(), wl.deployment(), wl.container(), wl.imageTag(), wl.replicas(),
            wl.cpuRequestCores(), 2.0, wl.memRequestMi(), wl.memLimitMi(), wl.cpuResizePolicy(),
            wl.cpuResizeRestartPolicy(), wl.javaToolOptions(), wl.readinessProbe(), wl.startupProbe(),
            wl.runAsNonRoot(), wl.allowPrivilegeEscalation(), wl.sidecars(), wl.readyPods(),
            wl.livenessProbe(), wl.livenessPath(), wl.readinessPath(), wl.livenessBudgetSeconds(),
            wl.startupBudgetSeconds(), wl.startupInitialDelaySeconds(), wl.readinessInitialDelaySeconds(),
            wl.terminationGracePeriodSeconds(), wl.preStopSleepSeconds());
        var r = sensor.sizeMemory(new Facts(twoCpu, base.runtime(), base.profile(), null, null), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.gc()).isEqualTo("G1GC");
    }

    private static final SensorService.CpuParams CPU_POLICY =
        new SensorService.CpuParams(1.5, 50, 120, 100, 1, 64);

    @Test
    void sizeCpu_requestFromP95_limitUnchanged() throws IOException {
        // p95 0.31 cores * 1.5 = 465m -> roundUp(50m) = 500m; limit 1 stays "1".
        var r = sensor.sizeCpu(fixture("baseline"), CPU_POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.requestsCpu()).isEqualTo("500m");
        assertThat(r.limitsCpu()).isEqualTo("1");
        assertThat(r.clampedToLimit()).isFalse();
        assertThat(r.evidence().cpuUsageP95Cores()).isEqualTo(0.31);
    }

    @Test
    void sizeCpu_clampsRequestToLimit() throws IOException {
        // p95 0.667 * 1.5 = 1000.5m -> roundUp(50m) = 1050m > limit 1 -> capped to 1000m, flagged.
        var r = sensor.sizeCpu(fixture("cpu-bound"), CPU_POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.requestsCpu()).isEqualTo("1000m");
        assertThat(r.limitsCpu()).isEqualTo("1");
        assertThat(r.clampedToLimit()).isTrue();
        assertThat(r.note()).contains("1050m").contains("CPU-bound");
    }

    @Test
    void sizeCpu_blockedWithoutP95() throws IOException {
        var r = sensor.sizeCpu(fixture("crac"), CPU_POLICY);   // fixture has no cpuUsageP95Cores
        assertThat(r.status()).isEqualTo("BLOCKED");
        assertThat(r.reason()).contains("CPU usage p95");
    }

    @Test
    void tenRunsAreIdentical() throws IOException {
        var facts = fixture("baseline");
        SizeResult first = sensor.sizeMemory(facts, POLICY);
        for (int i = 0; i < 10; i++) {
            assertThat(sensor.sizeMemory(facts, POLICY)).isEqualTo(first);
        }
    }
}
