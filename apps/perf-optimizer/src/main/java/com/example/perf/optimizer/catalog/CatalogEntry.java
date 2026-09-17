package com.example.perf.optimizer.catalog;

import java.util.List;
import java.util.Map;

/**
 * One catalog rule (from {@code catalog/findings.yaml}). The evaluator reads
 * {@code detector} (SpEL boolean over facts), {@code requires} (fact paths that
 * must be non-null or the finding is NOT_EVALUABLE), {@code prereqs} (guard ids
 * that must be satisfied or the finding is BLOCKED), {@code compute} (name → SpEL
 * producing a value shown as evidence and used by templates), {@code evidence}
 * (fact paths rendered as measured evidence), and {@code gain} (SpEL string).
 *
 * @param guard true for guard rules (e.g. profile-window-is-warm): a satisfied
 *              guard is a met prerequisite, an unsatisfied one blocks dependents.
 */
public record CatalogEntry(
    String id,
    String title,
    Severity severity,
    Effort effort,
    boolean guard,
    String detector,
    List<String> requires,
    List<String> prereqs,
    String reason,
    Map<String, String> compute,
    List<String> evidence,
    String gain,
    Fix fix,
    String learnMore
) {}
