package com.example.perf.optimizer.explain;

import com.example.perf.optimizer.catalog.Catalog;
import com.example.perf.optimizer.catalog.Evaluator;
import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.facts.Facts;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The artifact half of acceptance criterion 3: artifacts are rendered
 * deterministically in Java and carry the exact computed values, and the CRaC
 * Dockerfile is the golden one (correct tag/flags, none of the known anti-patterns).
 */
class TemplateRendererTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private final Evaluator evaluator = new Evaluator(new Catalog());
    private final TemplateRenderer renderer = new TemplateRenderer();

    private Facts baseline() throws IOException {
        try (var in = getClass().getResourceAsStream("/fixtures/baseline.json")) {
            return MAPPER.readValue(in, Facts.class);
        }
    }

    private Finding finding(List<Finding> findings, String id) {
        return findings.stream().filter(f -> f.id().equals(id)).findFirst().orElseThrow();
    }

    @Test
    void memoryArtifactCarriesComputedValues() throws IOException {
        var facts = baseline();
        var artifact = renderer.render(finding(evaluator.evaluate(facts), "memory-over-provisioned"), facts);
        assertThat(artifact)
            .contains("memory: \"512Mi\"")
            .contains("memory: \"768Mi\"")
            .contains("cpu: \"1\"")   // current CPU preserved (composes with the cpu-boost patch)
            .contains("-XX:+UseSerialGC")
            .contains("-XX:MaxRAMPercentage=75");
        assertThat(artifact).doesNotContain("{{");
    }

    @Test
    void cpuBoostArtifactHasResizePolicyAndKeepsMemory() throws IOException {
        var facts = baseline();
        var artifact = renderer.render(finding(evaluator.evaluate(facts), "startup-cpu-bound"), facts);
        assertThat(artifact)
            .contains("resizePolicy")
            .contains("restartPolicy: NotRequired")
            .contains("cpu: \"2\"")            // boot boost
            .contains("2048Mi");              // current memory preserved in the resize map
        assertThat(artifact).doesNotContain("{{");
    }

    @Test
    void checkpointArtifactIsTheGoldenCracDockerfile() throws IOException {
        var facts = baseline();
        var artifact = renderer.render(finding(evaluator.evaluate(facts), "startup-checkpointable"), facts);
        // Golden markers:
        assertThat(artifact)
            .contains("azul/zulu-openjdk:25-jdk-crac-latest")
            .contains("-Dspring.context.checkpoint=onRefresh")
            .contains("-XX:CRaCEngine=warp")
            .contains("-XX:CRaCRestoreFrom=/opt/crac-files");
        // Known anti-patterns must be absent:
        assertThat(artifact)
            .doesNotContain("amazoncorretto:25-crac")
            .doesNotContain("jcmd")
            .doesNotContain("JDK.checkpoint");
        // Includes the CRaC readiness hook for UnicornPublisher (item 8):
        assertThat(artifact)
            .contains("org.crac.Resource")
            .contains("beforeCheckpoint")
            .contains("afterRestore")
            .contains("UnicornPublisher");
    }

    @Test
    void renderingIsDeterministic() throws IOException {
        var facts = baseline();
        var f = finding(evaluator.evaluate(facts), "memory-over-provisioned");
        var first = renderer.render(f, facts);
        for (int i = 0; i < 10; i++) {
            assertThat(renderer.render(f, facts)).isEqualTo(first);
        }
    }
}
