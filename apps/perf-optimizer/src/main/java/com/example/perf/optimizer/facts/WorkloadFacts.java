package com.example.perf.optimizer.facts;

import java.util.List;

/**
 * Desired-state facts read from the Kubernetes API (read-only): the Deployment
 * and its Pods/HPA. Memory is in MiB and CPU in whole cores so the catalog SpEL
 * reads naturally (e.g. {@code limits.memory / rss.peak}). Any field may be null
 * when the source is unavailable — the evaluator gates on {@code requires}.
 *
 * @param namespace       Kubernetes namespace (also the app container name here)
 * @param deployment      Deployment name == Pyroscope service_name
 * @param container       app container name
 * @param imageTag        image tag of the app container (e.g. "latest", "crac", "aot")
 * @param replicas        desired replica count
 * @param cpuRequestCores requests.cpu in cores (e.g. 0.25 for 250m); null if unset
 * @param cpuLimitCores   limits.cpu in cores; null if unset
 * @param memRequestMi    requests.memory in MiB; null if unset
 * @param memLimitMi      limits.memory in MiB; null if unset
 * @param cpuResizePolicy true when the container declares a CPU resizePolicy (in-place resize enabled)
 * @param javaToolOptions value of the JAVA_TOOL_OPTIONS env var, or null if unset
 * @param sidecars        names of non-app containers in the pod (e.g. "perf-profiler")
 * @param hpaPresent      whether an HPA targets this Deployment
 * @param hpaMetricType   the HPA metric source type ("Resource" | "ContainerResource" | ...), or null
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
    String javaToolOptions,
    List<String> sidecars,
    boolean hpaPresent,
    String hpaMetricType
) {
    /** True when at least one non-app (sidecar) container is present in the pod. */
    public boolean sidecarsPresent() {
        return sidecars != null && !sidecars.isEmpty();
    }
}
