package com.example.perf.sensor;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The skill pack must be generic: no application names in any skill file. This
 * guards the reuse claim — the skills optimize ANY Java service on EKS, and the
 * app-specific values are filled from the app's own pom.xml at run time.
 */
class SkillDebrandingTest {

    // Case-insensitive substrings that would leak this workshop's app into the skills.
    private static final List<String> FORBIDDEN = List.of("unicorn", "store-spring", "storeapplication");

    @Test
    void noApplicationNamesInSkillPack() throws IOException {
        Path skills = Path.of("skills");
        assertThat(Files.isDirectory(skills)).as("skills/ dir present").isTrue();
        try (Stream<Path> files = Files.walk(skills)) {
            var offenders = files
                .filter(Files::isRegularFile)
                .flatMap(p -> {
                    try {
                        String lower = Files.readString(p).toLowerCase();
                        return FORBIDDEN.stream()
                            .filter(lower::contains)
                            .map(tok -> p + " contains \"" + tok + "\"");
                    } catch (IOException e) {
                        return Stream.of(p + " unreadable: " + e.getMessage());
                    }
                })
                .toList();
            assertThat(offenders).as("app names in skill pack").isEmpty();
        }
    }

    // The SOP's sizing numbers live in sizing-policy.yaml as the single source of
    // truth. Guard the values so the file cannot silently drift from the policy the
    // SizeMemoryTest fixtures are pinned to.
    private static final Map<String, String> EXPECTED_POLICY = Map.of(
        "peakFactor", "1.40", "floorSafetyFactor", "1.90",
        "roundMi", "128", "warmSeconds", "120", "minSamples", "100",
        "minRequestRate", "1", "minDeltaMi", "64");

    @Test
    void sizingPolicyFileMatchesTheDocumentedPolicy() throws IOException {
        Path policy = Path.of("skills/java-on-eks-optimization/references/sizing-policy.yaml");
        assertThat(Files.isRegularFile(policy)).as("sizing-policy.yaml present").isTrue();
        String text = Files.readString(policy);
        EXPECTED_POLICY.forEach((k, v) ->
            assertThat(text).as("policy %s: %s", k, v).containsPattern(k + ":\\s*" + v + "\\b"));
        assertThat(text).as("floorFactor retired: requests == limits").doesNotContain("floorFactor");
    }
}
