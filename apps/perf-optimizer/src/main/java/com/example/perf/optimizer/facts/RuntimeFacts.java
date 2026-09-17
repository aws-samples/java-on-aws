package com.example.perf.optimizer.facts;

/**
 * Measured runtime facts. Memory is the container working-set (the OOM-relevant
 * figure Kubernetes evicts on), in MiB, from Prometheus cAdvisor series; heap
 * used/committed, GC name and effective CPU count come from the sidecar
 * {@code /dump?kind=heap} ({@code jcmd GC.heap_info} / {@code VM.flags}); startup
 * is Micrometer's {@code application.ready.time}. Any field may be null when the
 * source is unavailable — the evaluator gates on {@code requires}.
 *
 * @param rssFloorMi        working-set floor (idle) over the window, MiB
 * @param rssPeakMi         working-set peak over the window, MiB (sizing basis for limits)
 * @param heapUsedMi        heap used at dump time, MiB
 * @param heapCommittedMi   heap committed at dump time, MiB
 * @param gcName            collector name reported by the JVM (e.g. "SerialGC", "G1GC")
 * @param effectiveCpuCount JVM's effective processor count in the container
 * @param startupSeconds    measured startup (application.ready.time), seconds
 * @param restarts          restartCount of the app container
 * @param uptimeSeconds     seconds since the app container last (re)started (K8s), or null
 */
public record RuntimeFacts(
    Double rssFloorMi,
    Double rssPeakMi,
    Double heapUsedMi,
    Double heapCommittedMi,
    String gcName,
    Integer effectiveCpuCount,
    Double startupSeconds,
    Integer restarts,
    Double uptimeSeconds
) {}
