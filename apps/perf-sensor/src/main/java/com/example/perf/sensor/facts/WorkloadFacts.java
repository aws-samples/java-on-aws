package com.example.perf.sensor.facts;

import java.util.List;

/**
 * Desired-state facts read from the Kubernetes API (read-only): the Deployment
 * and its Pods. Memory is in MiB and CPU in whole cores. Any field may be null
 * when the source is unavailable. Extracted deterministically in code (not by an
 * LLM reading raw YAML) because every field here backs a scored checklist item.
 *
 * @param namespace          Kubernetes namespace
 * @param deployment         Deployment name == Pyroscope service_name
 * @param container          app container name
 * @param imageTag           image tag of the app container (e.g. "latest", "aot", "crac")
 * @param replicas           desired replica count
 * @param cpuRequestCores    requests.cpu in cores (e.g. 0.25 for 250m); null if unset
 * @param cpuLimitCores      limits.cpu in cores; null if unset
 * @param memRequestMi       requests.memory in MiB; null if unset
 * @param memLimitMi         limits.memory in MiB; null if unset
 * @param cpuResizePolicy    true when the container declares a CPU resizePolicy (in-place resize enabled)
 * @param cpuResizeRestartPolicy the CPU resizePolicy restart value (e.g. "NotRequired"), or null
 * @param javaToolOptions    value of the JAVA_TOOL_OPTIONS env var, or null if unset
 * @param readinessProbe     true when the app container declares a readinessProbe
 * @param sidecars           names of non-app containers in the representative pod (e.g. "perf-profiler")
 * @param readyPods          count of Running+Ready pods of the workload (fleet size actually measured)
 */
public record WorkloadFacts(
    String namespace,
    String deployment,
    String container,
    String imageTag,
    Integer replicas,
    Double cpuRequestCores,
    Double cpuLimitCores,
    Double memRequestMi,
    Double memLimitMi,
    boolean cpuResizePolicy,
    String cpuResizeRestartPolicy,
    String javaToolOptions,
    boolean readinessProbe,
    List<String> sidecars,
    Integer readyPods
) {
    /** True when at least one non-app (sidecar) container is present in the pod. */
    public boolean sidecarsPresent() {
        return sidecars != null && !sidecars.isEmpty();
    }
}
