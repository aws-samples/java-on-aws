package com.example.perf.optimizer.explain;

import java.util.List;

/**
 * The explain output for one finding. {@code rationale} and {@code expectedOutcome}
 * are written by the model; everything else — {@code evidenceLines},
 * {@code artifact}, {@code applyCommand}, {@code learnMore} — is computed/rendered
 * in Java, so the artifact and its values are identical across runs regardless of
 * the model.
 */
public record Explanation(
    String findingId,
    String rationale,
    List<String> evidenceLines,
    String artifact,
    String applyCommand,
    String expectedOutcome,
    String learnMore
) {}
