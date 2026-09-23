package com.example.perf.sensor.facts;

import java.util.List;

/**
 * Profile-derived facts from Pyroscope CPU + wall profiles over the window. Shares are
 * percentages of the WHOLE profile's self time (every leaf frame, not only the top-N
 * returned), computed in Java from the flame graph — deterministic, no LLM. Pyroscope
 * is not reachable through any MCP server; the sensor is the only source.
 *
 * @param topCpu            ranked hottest CPU leaf functions
 * @param topWall           ranked hottest wall (off-CPU/waiting) leaf functions
 * @param jitSharePct       % of CPU self time in JIT/C2 compiler frames
 * @param gcSharePct        % of CPU self time in GC frames
 * @param futexWallSharePct % of wall self time parked in futex/lock waits
 * @param samples           CPU profile sample count over the window, derived from Pyroscope's
 *                          tick total and its {@code metadata.sampleRate}; 0 = no profile data.
 *                          The sizing guard's {@code minSamples} is a floor on this ("a real
 *                          profile exists").
 */
public record ProfileFacts(
    List<Frame> topCpu,
    List<Frame> topWall,
    Double jitSharePct,
    Double gcSharePct,
    Double futexWallSharePct,
    long samples
) {}
