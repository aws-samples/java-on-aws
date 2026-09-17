package com.example.perf.optimizer.catalog;

/**
 * Lifecycle status of a finding for a service. Ordinal order is also the display
 * priority (most actionable first) used by the ranking comparator.
 */
public enum FindingStatus {
    /** The detector fired and all prerequisites are met — an actionable optimization. */
    OPEN,
    /** The detector fired but a prerequisite is unmet (e.g. profiling window not warm). */
    BLOCKED,
    /** Previously OPEN, now the detector no longer fires — the fix took effect. */
    RESOLVED,
    /** The detector did not fire and there is no prior OPEN state — nothing to do. */
    NOT_APPLICABLE,
    /** A required fact was unavailable, so the detector could not be evaluated. */
    NOT_EVALUABLE
}
