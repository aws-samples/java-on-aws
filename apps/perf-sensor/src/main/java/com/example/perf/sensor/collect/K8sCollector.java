package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.WorkloadFacts;
import io.kubernetes.client.custom.Quantity;
import io.kubernetes.client.openapi.apis.AppsV1Api;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.openapi.models.V1Container;
import io.kubernetes.client.openapi.models.V1Deployment;
import io.kubernetes.client.openapi.models.V1Pod;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Reads desired-state {@link WorkloadFacts} from the Kubernetes API (read-only):
 * the Deployment (resources, env, resizePolicy, readinessProbe, image, replicas)
 * and a running Pod (sidecars, restartCount, pod IP for {@code /dump}, pod name
 * for logs). Extraction is in code so the fields that back scored checklist items
 * are deterministic. Degrades gracefully — returns a {@link Snapshot} of nulls
 * when the API is unreachable.
 */
@Component
public class K8sCollector {

    private static final Logger logger = LoggerFactory.getLogger(K8sCollector.class);
    private static final double MIB = 1024.0 * 1024.0;

    /** Workload facts plus the extras the other collectors need. */
    public record Snapshot(WorkloadFacts workload, Integer restarts, String appPodIP,
                           String appPodName, String appContainer, Double uptimeSeconds) {}

    /** A Ready pod's name + IP (for per-pod fan-out, e.g. thread-dump sampling). */
    public record PodRef(String name, String ip) {}

    /**
     * Ready pod name+IP for a workload, newest first — for tools that must fan out
     * across pods (thread dumps). Empty when the workload/API is unavailable.
     */
    public List<PodRef> readyPodRefs(String namespace, String deployment) {
        try {
            var dep = apps.readNamespacedDeployment(deployment, namespace).execute();
            String selector = selector(dep.getSpec(), deployment);
            var pods = core.listNamespacedPod(namespace).labelSelector(selector).execute();
            if (pods.getItems() == null) {
                return List.of();
            }
            return pods.getItems().stream()
                .filter(K8sCollector::isReady)
                .sorted(java.util.Comparator.comparingLong(K8sCollector::startTimeEpoch).reversed())
                .map(p -> new PodRef(
                    p.getMetadata() == null ? null : p.getMetadata().getName(),
                    p.getStatus() == null ? null : p.getStatus().getPodIP()))
                .filter(r -> r.ip() != null)
                .toList();
        } catch (Exception e) {
            logger.warn("readyPodRefs failed ns={} deploy={}: {}", namespace, deployment, e.getMessage());
            return List.of();
        }
    }

    private final CoreV1Api core;
    private final AppsV1Api apps;
    private final String serviceLabel;

    public K8sCollector(CoreV1Api core, AppsV1Api apps,
                        @Value("${SERVICE_LABEL:app}") String serviceLabel) {
        this.core = core;
        this.apps = apps;
        this.serviceLabel = serviceLabel;
    }

    public Snapshot collect(String namespace, String deployment) {
        try {
            V1Deployment dep = apps.readNamespacedDeployment(deployment, namespace).execute();
            var spec = dep.getSpec();
            var replicas = spec != null ? spec.getReplicas() : null;
            var containers = spec != null && spec.getTemplate().getSpec() != null
                ? spec.getTemplate().getSpec().getContainers() : List.<V1Container>of();
            V1Container app = appContainer(containers, deployment);

            String imageTag = imageTag(app == null ? null : app.getImage());
            Double cpuReq = null, cpuLim = null, memReq = null, memLim = null;
            boolean cpuResize = false;
            String cpuResizeRestart = null;
            String javaToolOptions = null;
            boolean readinessProbe = false;
            if (app != null) {
                var res = app.getResources();
                if (res != null) {
                    cpuReq = cores(get(res.getRequests(), "cpu"));
                    cpuLim = cores(get(res.getLimits(), "cpu"));
                    memReq = mib(get(res.getRequests(), "memory"));
                    memLim = mib(get(res.getLimits(), "memory"));
                }
                if (app.getResizePolicy() != null) {
                    var cpuPolicy = app.getResizePolicy().stream()
                        .filter(p -> "cpu".equalsIgnoreCase(p.getResourceName()))
                        .findFirst().orElse(null);
                    if (cpuPolicy != null) {
                        cpuResize = true;
                        cpuResizeRestart = cpuPolicy.getRestartPolicy();
                    }
                }
                if (app.getEnv() != null) {
                    // findFirst() on the EnvVar, THEN map to its value: a JAVA_TOOL_OPTIONS
                    // entry with a null value (e.g. cleared to empty, not removed) would make
                    // .map(getValue).findFirst() call Optional.of(null) -> NPE, which crashed
                    // the whole snapshot (workload/uptime null -> sizeMemory BLOCKED).
                    javaToolOptions = app.getEnv().stream()
                        .filter(e -> "JAVA_TOOL_OPTIONS".equals(e.getName()))
                        .findFirst()
                        .map(io.kubernetes.client.openapi.models.V1EnvVar::getValue)
                        .orElse(null);
                }
                readinessProbe = app.getReadinessProbe() != null;
            }

            // Resolve pods from the workload's OWN selector (not an assumed label), then
            // measure a REPRESENTATIVE pod: Running + Ready + not-terminating, newest by
            // start time. This is correct at any replica count and never reads a
            // terminating pod mid-rollout. readyPods records the fleet size measured.
            String selector = selector(spec, deployment);
            List<String> sidecars = new ArrayList<>();
            Integer restarts = null;
            String podIP = null;
            String podName = null;
            Double uptimeSeconds = null;
            Integer readyPods = null;
            var pods = core.listNamespacedPod(namespace).labelSelector(selector).execute();
            if (pods.getItems() != null) {
                var ready = pods.getItems().stream().filter(K8sCollector::isReady).toList();
                readyPods = ready.size();
                V1Pod pod = ready.stream().max(java.util.Comparator.comparing(K8sCollector::startTimeEpoch))
                    .orElse(null);
                if (pod != null) {
                    if (pod.getMetadata() != null) {
                        podName = pod.getMetadata().getName();
                    }
                    if (pod.getStatus() != null) {
                        podIP = pod.getStatus().getPodIP();
                        if (pod.getStatus().getContainerStatuses() != null) {
                            var appStatus = pod.getStatus().getContainerStatuses().stream()
                                .filter(cs -> deployment.equals(cs.getName()))
                                .findFirst().orElse(null);
                            if (appStatus != null) {
                                restarts = appStatus.getRestartCount();
                                if (appStatus.getState() != null && appStatus.getState().getRunning() != null
                                    && appStatus.getState().getRunning().getStartedAt() != null) {
                                    var startedAt = appStatus.getState().getRunning().getStartedAt();
                                    uptimeSeconds = (double) java.time.Duration
                                        .between(startedAt.toInstant(), java.time.Instant.now()).getSeconds();
                                }
                            }
                        }
                    }
                    if (pod.getSpec() != null && pod.getSpec().getContainers() != null) {
                        pod.getSpec().getContainers().stream()
                            .map(V1Container::getName)
                            .filter(n -> !deployment.equals(n))
                            .forEach(sidecars::add);
                    }
                }
            }

            var workload = new WorkloadFacts(namespace, deployment,
                app == null ? deployment : app.getName(), imageTag, replicas,
                cpuReq, cpuLim, memReq, memLim, cpuResize, cpuResizeRestart,
                javaToolOptions, readinessProbe, sidecars, readyPods);
            return new Snapshot(workload, restarts, podIP, podName, workload.container(), uptimeSeconds);
        } catch (Exception e) {
            logger.warn("K8s collect failed ns={} deploy={}: {}", namespace, deployment, e.toString(), e);
            return new Snapshot(null, null, null, null, null, null);
        }
    }

    /** Label selector from the Deployment's own matchLabels; falls back to serviceLabel=deployment. */
    private String selector(io.kubernetes.client.openapi.models.V1DeploymentSpec spec, String deployment) {
        if (spec != null && spec.getSelector() != null && spec.getSelector().getMatchLabels() != null
            && !spec.getSelector().getMatchLabels().isEmpty()) {
            return spec.getSelector().getMatchLabels().entrySet().stream()
                .map(e -> e.getKey() + "=" + e.getValue())
                .collect(java.util.stream.Collectors.joining(","));
        }
        return serviceLabel + "=" + deployment;
    }

    /** Running, Ready, and not being deleted. */
    private static boolean isReady(V1Pod pod) {
        if (pod.getMetadata() != null && pod.getMetadata().getDeletionTimestamp() != null) {
            return false;
        }
        var status = pod.getStatus();
        if (status == null || !"Running".equals(status.getPhase()) || status.getConditions() == null) {
            return false;
        }
        return status.getConditions().stream()
            .anyMatch(c -> "Ready".equals(c.getType()) && "True".equals(c.getStatus()));
    }

    /** Pod start time as epoch millis (0 if unknown) — newest wins as the representative pod. */
    private static long startTimeEpoch(V1Pod pod) {
        if (pod.getStatus() != null && pod.getStatus().getStartTime() != null) {
            return pod.getStatus().getStartTime().toInstant().toEpochMilli();
        }
        return 0L;
    }

    private static V1Container appContainer(List<V1Container> containers, String deployment) {
        if (containers == null || containers.isEmpty()) return null;
        return containers.stream()
            .filter(c -> deployment.equals(c.getName()))
            .findFirst()
            .orElse(containers.getFirst());
    }

    private static Quantity get(Map<String, Quantity> m, String key) {
        return m == null ? null : m.get(key);
    }

    private static Double cores(Quantity q) {
        return q == null ? null : q.getNumber().doubleValue();
    }

    private static Double mib(Quantity q) {
        return q == null ? null : q.getNumber().doubleValue() / MIB;
    }

    /** Tag after the last ':' in an image ref; "latest" when none. */
    static String imageTag(String image) {
        if (image == null || image.isBlank()) return null;
        int slash = image.lastIndexOf('/');
        int colon = image.lastIndexOf(':');
        return colon > slash ? image.substring(colon + 1) : "latest";
    }
}
