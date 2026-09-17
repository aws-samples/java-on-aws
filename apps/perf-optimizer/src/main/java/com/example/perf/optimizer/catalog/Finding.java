package com.example.perf.optimizer.catalog;

import java.util.List;
import java.util.Map;

/**
 * The evaluator's output for one catalog rule against one fact set. All values
 * are computed by Java from measured facts — never by the model.
 *
 * @param id        catalog id
 * @param title     human title
 * @param severity  severity
 * @param status    lifecycle status
 * @param effort    fix effort / ladder stage
 * @param gain      short expected-gain string (rendered from computed values), or null
 * @param learnMore docs link
 * @param evidence  rendered measured-evidence lines
 * @param computed  computed values (name → value) used as evidence and by templates
 * @param fix       how/where to fix
 * @param reason    explanation for BLOCKED / NOT_EVALUABLE / guard advice, else null
 * @param delta     realized before→after lines for RESOLVED findings, else null
 */
public record Finding(
    String id,
    String title,
    Severity severity,
    FindingStatus status,
    Effort effort,
    String gain,
    String learnMore,
    List<String> evidence,
    Map<String, Object> computed,
    Fix fix,
    String reason,
    List<String> delta
) {
    public boolean isOpen() {
        return status == FindingStatus.OPEN;
    }
}
