package com.example.perf.sensor.facts;

import java.util.List;

/**
 * Profile-derived facts from Pyroscope CPU + wall profiles over the window.
 * Shares are percentages of total samples for the profile, computed in Java from
 * leaf self-times (deterministic, no LLM). Pyroscope is not reachable through any
 * MCP server — the sensor is the only source.
 *
 * @param topCpu            ranked hottest CPU leaf functions
 * @param topWall           ranked hottest wall (off-CPU/waiting) leaf functions
 * @param jitSharePct       % of CPU samples in JIT/C2 compiler frames
 * @param gcSharePct        % of CPU samples in GC frames
 * @param futexWallSharePct % of wall samples parked in futex/lock waits
 * @param samples           CPU profile sample count over the window (Pyroscope numTicks converted from its tick unit; 100 samples ≈ 1 s of profiled CPU at the 10 ms interval)
 *                          (profiled-time units — nanoseconds for cpu/wall, NOT a literal
 *                          sample count); 0 = no profile data. The sizing guard's
 *                          {@code minSamples} is a floor on this weight ("a real profile exists").
 */
public record ProfileFacts(
    List<Frame> topCpu,
    List<Frame> topWall,
    Double jitSharePct,
    Double gcSharePct,
    Double futexWallSharePct,
    long samples
) {}
