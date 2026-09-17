package com.example.perf.optimizer.facts;

import java.util.List;

/**
 * Profile-derived facts from Pyroscope CPU + wall profiles over the window.
 * Shares are percentages of total samples for the profile. {@code warmupWindow}
 * is the guard signal: true when the CPU profile is JIT/C2-compiler dominated
 * (a cold/warm-up window, not steady state), which must gate sizing findings.
 *
 * @param topCpu             ranked hottest CPU leaf functions
 * @param topWall            ranked hottest wall (off-CPU/waiting) leaf functions
 * @param jitSharePct        % of CPU samples in JIT/C2 compiler frames
 * @param gcSharePct         % of CPU samples in GC frames
 * @param futexWallSharePct  % of wall samples parked in futex/lock waits
 * @param warmupWindow       true if the CPU profile looks like a JIT warm-up storm
 * @param samples            total CPU samples observed (0 = no data)
 */
public record ProfileFacts(
    List<Frame> topCpu,
    List<Frame> topWall,
    Double jitSharePct,
    Double gcSharePct,
    Double futexWallSharePct,
    Boolean warmupWindow,
    long samples
) {}
