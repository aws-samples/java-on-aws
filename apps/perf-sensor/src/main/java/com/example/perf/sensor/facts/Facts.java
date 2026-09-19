package com.example.perf.sensor.facts;

/**
 * The typed fact set for one service, aggregated from all collectors. Any
 * sub-facts may be null when a source is unavailable; callers degrade gracefully.
 * {@code threads} is populated only when a thread dump is requested.
 */
public record Facts(
    WorkloadFacts workload,
    RuntimeFacts runtime,
    ProfileFacts profile,
    ThreadFacts threads
) {}
