package com.example.perf.collector;

import com.example.perf.collector.CollectorProperties.Platform;
import com.example.perf.collector.CollectorProperties.TargetJvm;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubernetes.client.openapi.ApiException;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.openapi.models.V1Pod;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * TargetResolver interface plus both platform implementations plus the
 * discovery loop in a single file.
 *
 * Split by responsibility:
 *   - TargetResolver (interface)     — "which JVMs are ours, here and now?"
 *   - Eks                            — K8s API + pod→PID via cgroup
 *   - Ecs                            — ECS task-metadata endpoint
 *   - Proc (nested)                  — /proc scanning (Java PIDs, container id)
 *   - Discovery                      — @Scheduled loop that calls resolve() +
 *                                      hands new PIDs to AsyncProfilerAttach
 */
public interface TargetResolver {

    List<TargetJvm> resolve();

    /** True if this collector should handle a dump request for the given target id. */
    boolean handles(String targetId);

    /** Resolves a target id (pod name or task id) to its local JVM PID, or -1. */
    long pidFor(String targetId);

    /** Service name for the target id (matches perf-profile/service), or null. */
    String serviceNameFor(String targetId);

    /** EKS DaemonSet implementation. Lists pods on its own node via K8s API. */
    @Component
    @ConditionalOnProperty(prefix = "perf.collector", name = "platform",
        havingValue = "eks", matchIfMissing = true)
    final class Eks implements TargetResolver {

        private static final Logger logger = LoggerFactory.getLogger(Eks.class);
        private static final String OPT_IN_LABEL = "perf-profile/service";
        private static final String VERSION_LABEL = "app.kubernetes.io/version";

        private final CoreV1Api k8s;
        private final CollectorProperties props;
        private final Proc proc;
        private final Map<String, TargetJvm> byPodName = new ConcurrentHashMap<>();

        public Eks(CoreV1Api k8s, CollectorProperties props, Proc proc) {
            this.k8s = k8s;
            this.props = props;
            this.proc = proc;
        }

        @Override
        public List<TargetJvm> resolve() {
            if (props.nodeName() == null || props.nodeName().isBlank()) {
                logger.warn("NODE_NAME is not set; EKS discovery disabled");
                return List.of();
            }
            try {
                var list = k8s.listPodForAllNamespaces()
                    .fieldSelector("spec.nodeName=" + props.nodeName())
                    .execute();
                var discovered = new ArrayList<TargetJvm>();
                var pids = proc.javaPids();
                byPodName.clear();

                for (V1Pod pod : list.getItems()) {
                    var labels = pod.getMetadata().getLabels();
                    if (labels == null) continue;
                    var serviceName = labels.get(OPT_IN_LABEL);
                    if (serviceName == null || serviceName.isBlank()) continue;
                    var podName = pod.getMetadata().getName();
                    var version = versionFrom(pod, labels);

                    var matchedPid = matchPidForPod(pod, pids);
                    if (matchedPid < 0) {
                        logger.debug("Pod {} labeled but no matching PID found yet", podName);
                        continue;
                    }
                    var t = new TargetJvm(matchedPid, serviceName, version, podName, Platform.EKS);
                    discovered.add(t);
                    byPodName.put(podName, t);
                }
                logger.info("EKS discovery: {} opted-in JVMs on node {}",
                    discovered.size(), props.nodeName());
                return discovered;
            } catch (ApiException e) {
                logger.error("K8s API error during discovery: {}", e.getResponseBody());
                return List.of();
            }
        }

        @Override
        public boolean handles(String podName) { return byPodName.containsKey(podName); }
        @Override
        public long pidFor(String podName) {
            var t = byPodName.get(podName);
            return t == null ? -1 : t.pid();
        }
        @Override
        public String serviceNameFor(String podName) {
            var t = byPodName.get(podName);
            return t == null ? null : t.serviceName();
        }

        private String versionFrom(V1Pod pod, Map<String, String> labels) {
            var v = labels.get(VERSION_LABEL);
            if (v != null && !v.isBlank()) return v;
            if (pod.getSpec() != null && pod.getSpec().getContainers() != null
                && !pod.getSpec().getContainers().isEmpty()) {
                var image = pod.getSpec().getContainers().getFirst().getImage();
                if (image != null) {
                    var colon = image.lastIndexOf(':');
                    if (colon > 0) return image.substring(colon + 1);
                }
            }
            return "unknown";
        }

        private long matchPidForPod(V1Pod pod, List<Long> javaPids) {
            if (pod.getStatus() == null || pod.getStatus().getContainerStatuses() == null) return -1;
            for (var cs : pod.getStatus().getContainerStatuses()) {
                var containerId = stripRuntimePrefix(cs.getContainerID());
                if (containerId == null) continue;
                for (var pid : javaPids) {
                    var id = proc.containerIdFor(pid);
                    if (id != null && id.startsWith(containerId)) return pid;
                }
            }
            return -1;
        }

        private static String stripRuntimePrefix(String containerId) {
            if (containerId == null) return null;
            var sep = containerId.indexOf("://");
            return sep >= 0 ? containerId.substring(sep + 3) : containerId;
        }
    }

    /** ECS sidecar implementation. Reads task metadata endpoint. */
    @Component
    @ConditionalOnProperty(prefix = "perf.collector", name = "platform",
        havingValue = "ecs")
    final class Ecs implements TargetResolver {

        private static final Logger logger = LoggerFactory.getLogger(Ecs.class);
        private static final ObjectMapper MAPPER = new ObjectMapper();

        private final Proc proc;
        private final software.amazon.awssdk.services.ecs.EcsClient ecs;
        private final RestClient rest = RestClient.builder().build();
        private final Map<String, TargetJvm> byTaskId = new ConcurrentHashMap<>();

        public Ecs(Proc proc, software.amazon.awssdk.services.ecs.EcsClient ecs) {
            this.proc = proc;
            this.ecs = ecs;
        }

        @Override
        public List<TargetJvm> resolve() {
            var metaUri = System.getenv("ECS_CONTAINER_METADATA_URI_V4");
            if (metaUri == null || metaUri.isBlank()) {
                logger.warn("ECS_CONTAINER_METADATA_URI_V4 is not set; ECS discovery disabled");
                return List.of();
            }
            try {
                var taskJson = rest.get().uri(metaUri + "/task").retrieve().body(String.class);
                var node = MAPPER.readTree(taskJson);
                var taskArn = node.path("TaskARN").asText("");
                var cluster = node.path("Cluster").asText("");
                var tags = fetchTaskTags(cluster, taskArn);
                var serviceName = tags.getOrDefault("perf-profile:service",
                    tags.get("perf-profile/service"));
                if (serviceName == null || serviceName.isBlank()) {
                    logger.info("Task is not opted in (no perf-profile:service tag)");
                    byTaskId.clear();
                    return List.of();
                }
                var taskId = extractTaskId(taskArn);
                var version = extractAppImageTag(node.path("Containers"));

                var javaPids = proc.javaPids();
                if (javaPids.isEmpty()) return List.of();

                var pid = javaPids.getFirst();  // one sibling Java container per task
                var t = new TargetJvm(pid, serviceName, version, taskId, Platform.ECS);
                byTaskId.clear();
                byTaskId.put(taskId, t);
                logger.info("ECS discovery: taskId={} service={} version={} pid={}",
                    taskId, serviceName, version, pid);
                return List.of(t);
            } catch (Exception e) {
                logger.error("ECS discovery failed: {}", e.getMessage());
                return List.of();
            }
        }

        @Override
        public boolean handles(String taskId) {
            for (var key : byTaskId.keySet()) {
                if (taskId.equals(key) || taskId.endsWith("/" + key)) return true;
            }
            return false;
        }
        @Override
        public long pidFor(String taskId) {
            var t = find(taskId);
            return t == null ? -1 : t.pid();
        }
        @Override
        public String serviceNameFor(String taskId) {
            var t = find(taskId);
            return t == null ? null : t.serviceName();
        }

        private TargetJvm find(String taskId) {
            var direct = byTaskId.get(taskId);
            if (direct != null) return direct;
            for (var e : byTaskId.entrySet()) {
                if (taskId.endsWith("/" + e.getKey())) return e.getValue();
            }
            return null;
        }

        private Map<String, String> fetchTaskTags(String cluster, String taskArn) {
            if (cluster == null || cluster.isBlank() || taskArn == null || taskArn.isBlank()) {
                return Map.of();
            }
            try {
                var resp = ecs.describeTasks(
                    software.amazon.awssdk.services.ecs.model.DescribeTasksRequest.builder()
                        .cluster(cluster)
                        .tasks(taskArn)
                        .include(software.amazon.awssdk.services.ecs.model.TaskField.TAGS)
                        .build());
                if (resp.tasks().isEmpty()) return Map.of();
                var tags = new java.util.HashMap<String, String>();
                for (var t : resp.tasks().getFirst().tags()) {
                    if (t.key() != null && t.value() != null) tags.put(t.key(), t.value());
                }
                return tags;
            } catch (Exception e) {
                logger.warn("ECS DescribeTasks failed for tags of {}: {}", taskArn, e.getMessage());
                return Map.of();
            }
        }

        private static String extractTaskId(String taskArn) {
            if (taskArn == null || taskArn.isBlank()) return "unknown";
            var last = taskArn.lastIndexOf('/');
            return last >= 0 ? taskArn.substring(last + 1) : taskArn;
        }

        private static String extractAppImageTag(JsonNode containers) {
            if (!containers.isArray()) return "unknown";
            for (var c : containers) {
                var name = c.path("Name").asText("");
                if ("perf-collector".equals(name)) continue;
                var image = c.path("Image").asText("");
                var colon = image.lastIndexOf(':');
                if (colon > 0) return image.substring(colon + 1);
            }
            return "unknown";
        }
    }

    /** /proc scanning helper for both resolvers. */
    @Component
    final class Proc {

        private static final Logger log = LoggerFactory.getLogger(Proc.class);

        public List<Long> javaPids() {
            var out = new ArrayList<Long>();
            try (var stream = Files.list(Path.of("/proc"))) {
                stream.forEach(p -> {
                    var n = p.getFileName().toString();
                    if (!n.chars().allMatch(Character::isDigit)) return;
                    long pid;
                    try { pid = Long.parseLong(n); } catch (NumberFormatException _) { return; }
                    if (isJava(pid)) out.add(pid);
                });
            } catch (IOException e) {
                log.warn("Failed to list /proc: {}", e.getMessage());
            }
            return out;
        }

        private boolean isJava(long pid) {
            try {
                var comm = Files.readString(Path.of("/proc", Long.toString(pid), "comm")).trim();
                return comm.startsWith("java");
            } catch (IOException _) { return false; }
        }

        /** Best-effort container-id extraction from /proc/&lt;pid&gt;/cgroup. */
        public String containerIdFor(long pid) {
            try {
                var cgroup = Files.readString(Path.of("/proc", Long.toString(pid), "cgroup"));
                for (var line : cgroup.split("\n")) {
                    var idx = -1;
                    for (var sep : new String[]{"/cri-containerd-", "/docker-", "/pod", "/"}) {
                        var found = line.lastIndexOf(sep);
                        if (found >= 0) { idx = found + sep.length(); break; }
                    }
                    if (idx > 0 && idx + 64 <= line.length()) {
                        var candidate = line.substring(idx, idx + 64);
                        if (candidate.chars().allMatch(c -> "0123456789abcdef".indexOf(c) >= 0)) {
                            return candidate;
                        }
                    }
                }
            } catch (IOException _) {}
            return null;
        }
    }

    /** Scheduled discovery + attach loop. Every N seconds asks the active resolver
     *  for opted-in JVMs, then ensures AsyncProfilerAttach has attached to each. */
    @Component
    final class Discovery {

        private static final Logger log = LoggerFactory.getLogger(Discovery.class);

        private final TargetResolver resolver;
        private final Profiler profiler;

        public Discovery(TargetResolver resolver, Profiler profiler) {
            this.resolver = resolver;
            this.profiler = profiler;
        }

        @Scheduled(
            initialDelayString = "5000",
            fixedDelayString = "${perf.collector.discovery-interval-seconds:30}000"
        )
        public void discover() {
            try {
                for (var t : resolver.resolve()) {
                    profiler.attachIfNeeded(t);
                }
            } catch (Exception e) {
                log.warn("Discovery cycle failed: {}", e.getMessage());
            }
        }
    }
}
