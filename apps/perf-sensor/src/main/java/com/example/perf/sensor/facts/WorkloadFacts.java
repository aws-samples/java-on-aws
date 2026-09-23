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
 * @param startupProbe       true when the app container declares a startupProbe
 * @param runAsNonRoot       true when the app container (or pod) securityContext sets runAsNonRoot: true
 * @param allowPrivilegeEscalation true when the app container ALLOWS privilege escalation (secure = false; Kubernetes defaults to true when unset)
 * @param sidecars           names of non-app containers in the representative pod (e.g. "perf-profiler")
 * @param readyPods          count of Running+Ready pods of the workload (fleet size actually measured)
 * @param livenessProbe      true when the app container declares a livenessProbe
 * @param livenessPath       httpGet path of the liveness probe, or null
 * @param readinessPath      httpGet path of the readiness probe, or null
 * @param livenessBudgetSeconds  liveness failureThreshold x periodSeconds (time a GC pause may stall before a restart), or null
 * @param startupBudgetSeconds   startup failureThreshold x periodSeconds (time the JVM may take to boot), or null
 * @param startupInitialDelaySeconds  startupProbe.initialDelaySeconds (0 when unset; padding, not a budget), or null when no probe
 * @param readinessInitialDelaySeconds readinessProbe.initialDelaySeconds (0 when unset), or null when no probe
 * @param terminationGracePeriodSeconds pod terminationGracePeriodSeconds (K8s default 30 when unset)
 * @param preStopSleepSeconds  seconds slept by a preStop exec/sleep hook (0 when no hook)
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
    boolean startupProbe,
    boolean runAsNonRoot,
    boolean allowPrivilegeEscalation,
    List<String> sidecars,
    Integer readyPods,
    boolean livenessProbe,
    String livenessPath,
    String readinessPath,
    Integer livenessBudgetSeconds,
    Integer startupBudgetSeconds,
    Integer startupInitialDelaySeconds,
    Integer readinessInitialDelaySeconds,
    Long terminationGracePeriodSeconds,
    Integer preStopSleepSeconds
) {}
