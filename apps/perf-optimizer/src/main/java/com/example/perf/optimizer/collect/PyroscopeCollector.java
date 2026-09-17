package com.example.perf.optimizer.collect;

import com.example.perf.optimizer.PyroscopeTool;
import com.example.perf.optimizer.facts.Frame;
import com.example.perf.optimizer.facts.ProfileFacts;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Derives {@link ProfileFacts} from Pyroscope CPU + wall profiles: hottest
 * frames, JIT/GC CPU shares, futex/park wall share, and the {@code warmupWindow}
 * guard (CPU profile dominated by JIT/C2 compiler frames == cold/warm-up, not
 * steady state). Shares are computed in Java from leaf self-times — deterministic,
 * no LLM.
 */
@Component
public class PyroscopeCollector {

    /** A CPU JIT share above this is treated as a warm-up window (gates sizing). */
    static final double JIT_WARMUP_THRESHOLD_PCT = 15.0;

    // Leaf-name substrings that identify JIT/C2 compiler, GC, and futex/park frames.
    private static final List<String> JIT = List.of(
        "PhaseChaitin", "PhaseIdealLoop", "PhaseLive", "PhaseCFG", "Compile::", "Compilation::",
        "CodeHeap", "C2Compiler", "C1_", "Compiler::", "OptoRuntime", "Matcher::", "PhaseChaitinp");
    private static final List<String> GC = List.of(
        "MarkSweep", "PSYoungGen", "PSScavenge", "G1", "GCTaskThread", "GenCollectedHeap",
        "SerialHeap", "CardTable", "VM_GenCollect", "gc/", "TenuredGeneration", "DefNewGeneration");
    private static final List<String> FUTEX = List.of(
        "futex", "Unsafe.park", "Unsafe_Park", "park(", "PlatformEvent", "pthread_cond",
        "ConcurrentBag", "Park::");

    private final PyroscopeTool pyroscope;

    public PyroscopeCollector(PyroscopeTool pyroscope) {
        this.pyroscope = pyroscope;
    }

    public ProfileFacts collect(String service, String fromIso, String toIso, int topN) {
        var cpu = pyroscope.profile(service, "cpu", fromIso, toIso, topN);
        var wall = pyroscope.profile(service, "wall", fromIso, toIso, topN);
        if (!cpu.hasSamples() && !wall.hasSamples()) {
            return new ProfileFacts(List.of(), List.of(), null, null, null, null, 0);
        }
        Double jit = cpu.hasSamples() ? share(cpu.frames(), JIT) : null;
        Double gc = cpu.hasSamples() ? share(cpu.frames(), GC) : null;
        Double futex = wall.hasSamples() ? share(wall.frames(), FUTEX) : null;
        Boolean warmup = jit == null ? null : jit > JIT_WARMUP_THRESHOLD_PCT;
        return new ProfileFacts(cpu.frames(), wall.frames(), jit, gc, futex, warmup, cpu.numTicks());
    }

    /** Sum of self% over frames whose name contains any of the substrings. */
    private static double share(List<Frame> frames, List<String> needles) {
        double sum = 0;
        for (var f : frames) {
            for (var n : needles) {
                if (f.name().contains(n)) {
                    sum += f.selfPct();
                    break;
                }
            }
        }
        return Math.round(sum * 10.0) / 10.0;
    }
}
