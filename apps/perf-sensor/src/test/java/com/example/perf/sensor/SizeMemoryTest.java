package com.example.perf.sensor;

import com.example.perf.sensor.SensorService.CpuParams;
import com.example.perf.sensor.SensorService.SizeParams;
import com.example.perf.sensor.SensorService.SizeResult;
import com.example.perf.sensor.facts.Facts;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ObjectNode;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * sizeMemory / sizeCpu arithmetic + guard over JSON fact fixtures. Pins the numbers the
 * workshop content shows and determinism (identical output across repeated runs). No
 * collectors, no LLM. The policy values are the ones in
 * {@code skills/java-on-eks-optimization/references/sizing-policy.yaml} (guarded by
 * {@link SkillDebrandingTest}). Fixtures are parsed strictly so a renamed or removed fact
 * field fails here instead of silently reading as null.
 */
class SizeMemoryTest {

    // Strict on unknown fields (drift), lenient on absent primitives (fixtures list only the
    // facts a test needs; Jackson 3 fails on those by default).
    static final JsonMapper MAPPER = JsonMapper.builder()
        .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
        .disable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
        .build();

    // sizing-policy.yaml: peakFactor, floorSafetyFactor, roundMi, warmSeconds, minSamples, minRequestRate, minDeltaMi
    static final SizeParams POLICY = new SizeParams(1.40, 1.50, 128, 120, 100, 1, 64);
    // sizing-policy.yaml: cpuFactor, roundMillicores, warmSeconds, minSamples, minRequestRate, minDeltaMi
    static final CpuParams CPU_POLICY = new CpuParams(1.5, 50, 120, 100, 1, 64);

    private final SensorService sensor = new SensorService(null, null, null, null, null, null);

    static Facts fixture(String name) throws IOException {
        try (var in = SizeMemoryTest.class.getResourceAsStream("/fixtures/" + name + ".json")) {
            assertThat(in).as("fixture %s", name).isNotNull();
            return MAPPER.readValue(in, Facts.class);
        }
    }

    /** The fixture with one workload field overridden, without spelling out the 27-field record. */
    private static Facts fixtureWithWorkload(String name, String field, double value) throws IOException {
        try (var in = SizeMemoryTest.class.getResourceAsStream("/fixtures/" + name + ".json")) {
            var tree = (ObjectNode) MAPPER.readTree(in);
            ((ObjectNode) tree.get("workload")).put(field, value);
            return MAPPER.treeToValue(tree, Facts.class);
        }
    }

    @Test
    void baseline_sizesToTheWorkshopNumber_serialGc() throws IOException {
        // floor 377, peak 517: limits = roundUp(max(723.8, 565.5), 128) = 768; requests == limits.
        var r = sensor.sizeMemory(fixture("baseline"), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.requests().memory()).isEqualTo("768Mi");
        assertThat(r.limits().memory()).isEqualTo("768Mi");
        assertThat(r.maxRamPercentage()).isEqualTo(75);
        assertThat(r.initialRamPercentage()).isEqualTo(50);
        assertThat(r.gc()).isEqualTo("SerialGC");
        assertThat(r.evidence().workingSetFloorMi()).isEqualTo(377.0);
        assertThat(r.evidence().workingSetPeakMi()).isEqualTo(517.0);
    }

    @Test
    void genericApp_sameArithmetic_noAppNameInvolved() throws IOException {
        var r = sensor.sizeMemory(fixture("generic-app"), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.limits().memory()).isEqualTo("768Mi");
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
    void crac_sizesSmall_peakFactorDominates() throws IOException {
        // floor 190, peak 210: limits = roundUp(max(294, 285), 128) = 384; requests == limits.
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
        assertThat(r.evidence().workingSetFloorMi()).isEqualTo(400.0);
    }

    @Test
    void missingFacts_blocked() {
        var r = sensor.sizeMemory(new Facts(null, null, null, null), POLICY);
        assertThat(r.status()).isEqualTo("BLOCKED");
        assertThat(r.reason()).contains("insufficient measurement");
    }

    @Test
    void gcIsG1_whenMoreThanOneCpu() throws IOException {
        var r = sensor.sizeMemory(fixtureWithWorkload("baseline", "cpuLimitCores", 2.0), POLICY);
        assertThat(r.status()).isEqualTo("OK");
        assertThat(r.gc()).isEqualTo("G1GC");
    }

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

    @Test
    void fixturesAreParsedStrictly_unknownFieldFails() {
        assertThatThrownBy(() -> MAPPER.readValue("{\"runtime\":{\"rssPeakMi\":1}}", Facts.class))
            .hasMessageContaining("rssPeakMi");
    }

    @Test
    void quantities() {
        assertThat(SensorService.quantity(1.0)).isEqualTo("1");
        assertThat(SensorService.quantity(0.25)).isEqualTo("250m");
        assertThat(SensorService.roundUpMi(689.0, 128)).isEqualTo("768Mi");
        assertThat(SensorService.roundUpMi(768.0, 128)).isEqualTo("768Mi");
        assertThat(SensorService.roundUpMi(768.1, 128)).isEqualTo("896Mi");
    }
}
