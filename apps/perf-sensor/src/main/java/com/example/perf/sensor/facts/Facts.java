package com.example.perf.sensor.facts;

/**
 * The typed fact set for one service over one window, aggregated from all collectors.
 * Any sub-fact may be null when a source is unavailable; callers degrade gracefully.
 * Thread facts are not part of this set: they are collected on demand by
 * {@code threadDump} / {@code diagnoseBlocking} because a dump is a live sample, not a
 * window aggregate.
 */
public record Facts(
    WorkloadFacts workload,
    RuntimeFacts runtime,
    ProfileFacts profile,
    JfrFacts jfr
) {}
