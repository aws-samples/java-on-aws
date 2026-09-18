package com.example.perf.optimizer.catalog;

import com.example.perf.optimizer.facts.Facts;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Evaluator tests over JSON fact fixtures → expected finding statuses and
 * computed values. Also pins determinism (identical output across repeated runs)
 * and the RESOLVED transition, which back acceptance criteria 1–3.
 */
class EvaluatorTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private final Evaluator evaluator = new Evaluator(new Catalog());

    private Facts fixture(String name) throws IOException {
        try (var in = getClass().getResourceAsStream("/fixtures/" + name + ".json")) {
            assertThat(in).as("fixture %s", name).isNotNull();
            return MAPPER.readValue(in, Facts.class);
        }
    }

    private Map<String, Finding> byId(List<Finding> findings) {
        return findings.stream().collect(Collectors.toMap(Finding::id, Function.identity()));
    }

    @Test
    void baseline_opensTheThreeSessionFindings_withComputedSizing() throws IOException {
        var f = byId(evaluator.evaluate(fixture("baseline")));

        assertThat(f.get("profile-window-is-warm").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("startup-cpu-bound").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("startup-checkpointable").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("hpa-metric-with-sidecar").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("blocking-call-in-request-path").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);

        // Computed sizing lands inside the acceptance ranges (384–576Mi / 640–896Mi, SerialGC).
        var mem = f.get("memory-over-provisioned").computed();
        assertThat(mem.get("requests.memory")).isEqualTo("512Mi");
        assertThat(mem.get("limits.memory")).isEqualTo("768Mi");
        assertThat(mem.get("jvm.gc")).isEqualTo("SerialGC");
        assertThat(mem.get("jvm.maxRamPercentage")).isEqualTo(75);
        assertThat(f.get("memory-over-provisioned").gain()).isEqualTo("memory -63%");
    }

    @Test
    void warmupWindow_blocksSizingFindings_andSurfacesGuardAdvice() throws IOException {
        var f = byId(evaluator.evaluate(fixture("warmup-window")));

        assertThat(f.get("profile-window-is-warm").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("profile-window-is-warm").reason()).contains("warm-up");
        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.BLOCKED);
        assertThat(f.get("memory-over-provisioned").reason()).contains("warm-up");
        // startup-cpu-bound is NO LONGER gated on the warm window (startup is measured at boot):
        assertThat(f.get("startup-cpu-bound").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("startup-checkpointable").status()).isEqualTo(FindingStatus.OPEN);
    }

    @Test
    void idleWindow_blocksMemorySizing_withLoadObservedReason() throws IOException {
        var f = byId(evaluator.evaluate(fixture("idle")));
        // Warm, but no load observed (flat working-set, request rate 0):
        assertThat(f.get("load-observed").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("load-observed").reason()).contains("No load observed");
        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.BLOCKED);
        assertThat(f.get("memory-over-provisioned").reason()).contains("No load observed");
        // startup-cpu-bound is independent of load:
        assertThat(f.get("startup-cpu-bound").status()).isEqualTo(FindingStatus.OPEN);
    }

    @Test
    void flatWindowUnderLoad_sizesLimitFromFloorSafetyTerm() throws IOException {
        var f = byId(evaluator.evaluate(fixture("load-flat")));
        // requestRate>1 satisfies load-observed even though the working-set is flat.
        assertThat(f.get("load-observed").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.OPEN);
        // limits = max(1.4*peak=574, 1.9*floor=760) -> 768Mi (floor term dominates, prevents under-size).
        assertThat(f.get("memory-over-provisioned").computed().get("limits.memory")).isEqualTo("768Mi");
    }

    @Test
    void rightSized_noSizingFindings_checkpointStillOpen() throws IOException {
        var f = byId(evaluator.evaluate(fixture("right-sized")));

        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("startup-cpu-bound").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("startup-checkpointable").status()).isEqualTo(FindingStatus.OPEN);
    }

    @Test
    void crac_fullyOptimized_startupResolvesAgainstPriorOpen() throws IOException {
        var f = byId(evaluator.evaluate(fixture("crac")));
        assertThat(f.get("startup-checkpointable").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("startup-cpu-bound").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);
        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.NOT_APPLICABLE);

        // With a prior OPEN state, the same facts report RESOLVED (the apply-loop delta case).
        var prior = Set.of("startup-checkpointable", "memory-over-provisioned", "startup-cpu-bound");
        var resolved = byId(evaluator.evaluate(fixture("crac"), prior));
        assertThat(resolved.get("startup-checkpointable").status()).isEqualTo(FindingStatus.RESOLVED);
    }

    @Test
    void blocking_opensWhenWallAndThreadEvidencePresent() throws IOException {
        var f = byId(evaluator.evaluate(fixture("blocking")));
        assertThat(f.get("blocking-call-in-request-path").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("blocking-call-in-request-path").severity()).isEqualTo(Severity.CRITICAL);
    }

    @Test
    void hpaResourceWithSidecar_opens() throws IOException {
        var f = byId(evaluator.evaluate(fixture("hpa-resource")));
        assertThat(f.get("hpa-metric-with-sidecar").status()).isEqualTo(FindingStatus.OPEN);
        assertThat(f.get("hpa-metric-with-sidecar").computed().get("metric.type")).isEqualTo("ContainerResource");
    }

    @Test
    void notEvaluable_whenRequiredFactsMissing() throws IOException {
        // Empty facts → memory sizing cannot be evaluated (no rss/limits).
        var f = byId(evaluator.evaluate(new Facts(null, null, null, null)));
        assertThat(f.get("memory-over-provisioned").status()).isEqualTo(FindingStatus.NOT_EVALUABLE);
        assertThat(f.get("startup-checkpointable").status()).isEqualTo(FindingStatus.NOT_EVALUABLE);
    }

    @Test
    void tenRunsAreIdentical() throws IOException {
        var facts = fixture("baseline");
        var first = evaluator.evaluate(facts);
        for (int i = 0; i < 10; i++) {
            assertThat(evaluator.evaluate(facts)).isEqualTo(first);
        }
    }

    @Test
    void rankingIsDeterministicAndSeverityOrdered() throws IOException {
        var findings = evaluator.evaluate(fixture("blocking"));
        // blocking-call (CRITICAL, OPEN) ranks ahead of startup-checkpointable (HIGH, OPEN).
        var ids = findings.stream().map(Finding::id).toList();
        assertThat(ids.indexOf("blocking-call-in-request-path"))
            .isLessThan(ids.indexOf("startup-checkpointable"));
    }
}
