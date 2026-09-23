package com.example.perf.sensor.facts;

/**
 * Measured runtime facts. Memory is the container working set (the figure Kubernetes
 * evicts on), in MiB, from Prometheus cAdvisor series scoped to the Ready pods; heap
 * used/committed, heap bounds and GC name come from the sidecar {@code /dump?kind=heap}
 * ({@code jcmd GC.heap_info} / {@code VM.flags}); startup comes from the pod log
 * ({@code Started}/{@code Restored} line, published by the sensor as
 * {@code perf_sensor_startup_seconds}), falling back to Micrometer
 * {@code application.ready.time}. Any field may be null when the source is unavailable.
 *
 * @param workingSetFloorMi  5th percentile of the working set over the window after the pod's
 *                           first minute, MiB (the idle footprint; the boot ramp is excluded)
 * @param workingSetPeakMi   working-set peak over the window, MiB (sizing basis for limits)
 * @param heapUsedMi         heap used at dump time, MiB
 * @param heapCommittedMi    heap committed at dump time, MiB
 * @param gcName             collector name reported by the JVM (e.g. "SerialGC", "G1GC")
 * @param effectiveCpuCount  JVM's effective processor count in the container
 * @param startupSeconds     measured startup of the slowest current pod, seconds
 * @param restarts           restartCount of the app container
 * @param uptimeSeconds      seconds since the app container last (re)started (K8s), or null
 * @param requestRatePerSec  HTTP request rate over the window (Micrometer), 0 if idle, null if unscraped
 * @param maxHeapMi          observed JVM MaxHeapSize (VM.flags), MiB — the real heap ceiling, image-independent
 * @param initialHeapMi      observed JVM InitialHeapSize (VM.flags), MiB
 * @param cpuUsageP95Cores   p95 of the container CPU usage rate over the window, cores (cAdvisor)
 * @param cpuThrottledRatio  CFS throttled seconds / CPU seconds used, current pod's lifetime minus its first 60 s, capped at 5 min; null while the pod is younger than 90 s (cAdvisor)
 * @param latencyMeanMs      mean HTTP request latency over the window, ms (Micrometer http_server_requests_seconds, non-actuator URIs)
 * @param latencyMaxMs       max HTTP request latency observed (Micrometer http_server_requests_seconds_max, non-actuator URIs), ms
 * @param lastTerminationReason reason of the app container's last termination (e.g. "OOMKilled"), or null
 */
public record RuntimeFacts(
    Double workingSetFloorMi,
    Double workingSetPeakMi,
    Double heapUsedMi,
    Double heapCommittedMi,
    String gcName,
    Integer effectiveCpuCount,
    Double startupSeconds,
    Integer restarts,
    Double uptimeSeconds,
    Double requestRatePerSec,
    Double maxHeapMi,
    Double initialHeapMi,
    Double cpuUsageP95Cores,
    Double cpuThrottledRatio,
    Double latencyMeanMs,
    Double latencyMaxMs,
    String lastTerminationReason
) {}
