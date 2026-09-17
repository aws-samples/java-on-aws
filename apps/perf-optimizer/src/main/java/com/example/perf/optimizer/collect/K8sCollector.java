package com.example.perf.optimizer.collect;

import com.example.perf.optimizer.facts.WorkloadFacts;
import io.kubernetes.client.custom.Quantity;
import io.kubernetes.client.openapi.apis.AppsV1Api;
import io.kubernetes.client.openapi.apis.AutoscalingV2Api;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.openapi.models.V1Container;
import io.kubernetes.client.openapi.models.V1Deployment;
import io.kubernetes.client.openapi.models.V1Pod;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Reads desired-state {@link WorkloadFacts} from the Kubernetes API (read-only):
 * the Deployment (resources, env, resizePolicy, image, replicas), a running Pod
 * (sidecars, restartCount, pod IP for {@code /dump}), and any HPA targeting the
 * Deployment. Degrades gracefully — returns a {@link Snapshot} of nulls when the
 * API is unreachable.
 */
@Component
public class K8sCollector {

    private static final Logger logger = LoggerFactory.getLogger(K8sCollector.class);
    private static final double MIB = 1024.0 * 1024.0;

    /** Workload facts plus the extras the other collectors need. */
    public record Snapshot(WorkloadFacts workload, Integer restarts, String appPodIP,
                           String appContainer, Double uptimeSeconds) {}

    private final CoreV1Api core;
    private final AppsV1Api apps;
    private final AutoscalingV2Api autoscaling;

    public K8sCollector(CoreV1Api core, AppsV1Api apps, AutoscalingV2Api autoscaling) {
        this.core = core;
        this.apps = apps;
        this.autoscaling = autoscaling;
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
            String javaToolOptions = null;
            if (app != null) {
                var res = app.getResources();
                if (res != null) {
                    cpuReq = cores(get(res.getRequests(), "cpu"));
                    cpuLim = cores(get(res.getLimits(), "cpu"));
                    memReq = mib(get(res.getRequests(), "memory"));
                    memLim = mib(get(res.getLimits(), "memory"));
                }
                if (app.getResizePolicy() != null) {
                    cpuResize = app.getResizePolicy().stream()
                        .anyMatch(p -> "cpu".equalsIgnoreCase(p.getResourceName()));
                }
                if (app.getEnv() != null) {
                    javaToolOptions = app.getEnv().stream()
                        .filter(e -> "JAVA_TOOL_OPTIONS".equals(e.getName()))
                        .map(io.kubernetes.client.openapi.models.V1EnvVar::getValue)
                        .findFirst().orElse(null);
                }
            }

            // A running pod: sidecar names, restartCount, pod IP.
            List<String> sidecars = new ArrayList<>();
            Integer restarts = null;
            String podIP = null;
            Double uptimeSeconds = null;
            var pods = core.listNamespacedPod(namespace).labelSelector("app=" + deployment).execute();
            if (pods.getItems() != null && !pods.getItems().isEmpty()) {
                V1Pod pod = pods.getItems().getFirst();
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

            // HPA targeting this Deployment.
            boolean hpaPresent = false;
            String hpaMetricType = null;
            var hpas = autoscaling.listNamespacedHorizontalPodAutoscaler(namespace).execute();
            if (hpas.getItems() != null) {
                for (var hpa : hpas.getItems()) {
                    var ref = hpa.getSpec() == null ? null : hpa.getSpec().getScaleTargetRef();
                    if (ref != null && deployment.equals(ref.getName())) {
                        hpaPresent = true;
                        if (hpa.getSpec().getMetrics() != null && !hpa.getSpec().getMetrics().isEmpty()) {
                            hpaMetricType = hpa.getSpec().getMetrics().getFirst().getType();
                        }
                        break;
                    }
                }
            }

            var workload = new WorkloadFacts(namespace, deployment,
                app == null ? deployment : app.getName(), imageTag, replicas,
                cpuReq, cpuLim, memReq, memLim, cpuResize, javaToolOptions,
                sidecars, hpaPresent, hpaMetricType);
            return new Snapshot(workload, restarts, podIP, workload.container(), uptimeSeconds);
        } catch (Exception e) {
            logger.warn("K8s collect failed ns={} deploy={}: {}", namespace, deployment, e.getMessage());
            return new Snapshot(null, null, null, null, null);
        }
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
