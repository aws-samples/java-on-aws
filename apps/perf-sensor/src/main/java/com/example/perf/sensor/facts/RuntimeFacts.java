package com.example.perf.sensor.facts;

/**
 * Measured runtime facts. Memory is the container working-set (the OOM-relevant
 * figure Kubernetes evicts on), in MiB, from Prometheus cAdvisor series; heap
 * used/committed, heap bounds and GC name come from the sidecar {@code /dump?kind=heap}
 * ({@code jcmd GC.heap_info} / {@code VM.flags}); startup is Micrometer's
 * {@code application.ready.time}. Any field may be null when the source is
 * unavailable. No MCP server provides these — the sensor is the only source.
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
 * @param requestRatePerSec HTTP request rate over the window (Micrometer), 0 if idle, null if unscraped
 * @param maxHeapMi         observed JVM MaxHeapSize (VM.flags), MiB — the real heap ceiling, image-independent
 * @param initialHeapMi     observed JVM InitialHeapSize (VM.flags), MiB
 * @param cpuUsageP95Cores  p95 of the container CPU usage rate over the window, cores (cAdvisor)
 * @param cpuThrottledRatio CFS throttled seconds / CPU seconds used, last ≤5 min of the current pod excluding its first 60 s; null while the pod is younger than 2 min (cAdvisor)
 * @param latencyMeanMs     mean HTTP request latency over the window, ms (Micrometer http_server_requests_seconds, non-actuator URIs)
 * @param latencyMaxMs      max HTTP request latency observed (Micrometer http_server_requests_seconds_max, non-actuator URIs), ms
 * @param lastTerminationReason reason of the app container's last termination (e.g. "OOMKilled"), or null
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
