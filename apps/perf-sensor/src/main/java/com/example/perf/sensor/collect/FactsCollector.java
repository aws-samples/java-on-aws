package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.Facts;
import com.example.perf.sensor.facts.ProfileFacts;
import com.example.perf.sensor.facts.RuntimeFacts;
import com.example.perf.sensor.facts.WorkloadFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/**
 * Orchestrates the collectors into one {@link Facts} for a service over a window.
 * In this workshop the Pyroscope {@code service_name}, the Deployment name, the
 * namespace and the app container name are the same string. Every collector
 * degrades to nulls independently, so partial environments still measure.
 * Thread facts are collected separately (only when a dump is requested).
 */
@Component
public class FactsCollector {

    private static final Logger logger = LoggerFactory.getLogger(FactsCollector.class);

    private final K8sCollector k8s;
    private final PrometheusClient prometheus;
    private final PyroscopeClient pyroscope;
    private final DumpCollector dump;
    private final JfrCollector jfr;

    public FactsCollector(K8sCollector k8s, PrometheusClient prometheus,
                          PyroscopeClient pyroscope, DumpCollector dump, JfrCollector jfr) {
        this.k8s = k8s;
        this.prometheus = prometheus;
        this.pyroscope = pyroscope;
        this.dump = dump;
        this.jfr = jfr;
    }

    /** Collect workload + runtime + profile facts (no thread dump). */
    public Facts collect(String service, int windowMinutes) {
        var mins = windowMinutes <= 0 ? 15 : windowMinutes;
        var to = Instant.now();
        var from = to.minus(Duration.ofMinutes(mins));

        var snap = k8s.collect(service, service);
        WorkloadFacts workload = snap.workload();
        String container = snap.appContainer() != null ? snap.appContainer() : service;
        // Scope cAdvisor facts to the pods that exist NOW: a pod replaced by a rollout earlier
        // in the window must not supply the peak, the p95 or the startup of the current one.
        String pods = snap.readyPodRegex();

        Double rssFloor = prometheus.workingSetFloorMi(service, container, pods, mins);
        Double rssPeak = prometheus.workingSetPeakMi(service, container, pods, mins);
        Double startup = currentStartup(service, snap.readyPodNames());
        // Traffic facts (Micrometer, fleet-wide) over the window clipped to the current pod's
        // lifetime, so a pod that has seen no load yet does not inherit the previous pod's traffic.
        int trafficMins = snap.uptimeSeconds() == null ? mins
            : (int) Math.max(1, Math.min(mins, Math.floor(snap.uptimeSeconds() / 60.0)));
        Double requestRate = prometheus.requestRatePerSec(service, trafficMins);
        Double cpuP95 = prometheus.cpuUsageP95Cores(service, container, pods, mins);
        // Throttling: last 5 minutes at most, and never the pod's first 60 s (boot JIT saturates
        // the quota by design). Whole minutes; null while the pod is younger than 2 min.
        Double throttled = null;
        if (snap.uptimeSeconds() != null && snap.uptimeSeconds() >= 120) {
            int throttleMins = (int) Math.min(Math.min(mins, 5), Math.floor((snap.uptimeSeconds() - 60) / 60.0));
            throttled = prometheus.cpuThrottledRatio(service, container, pods, throttleMins);
        }
        Double latencyMean = prometheus.latencyMeanMs(service, trafficMins);
        Double latencyMax = prometheus.latencyMaxMs(service, trafficMins);
        var heap = dump.heap(snap.appPodIP());
        var ring = jfr.collect(snap.appPodIP(), snap.appPodName());
        // effectiveCpuCount: what the JVM itself reported (jdk.ContainerConfiguration) when the
        // ring is available; otherwise the CPU limit rounded up to whole processors.
        Integer effectiveCpu = ring != null && ring.container() != null && ring.container().effectiveCpuCount() != null
            ? ring.container().effectiveCpuCount()
            : (workload != null && workload.cpuLimitCores() != null) ? (int) Math.ceil(workload.cpuLimitCores()) : null;
        var runtime = new RuntimeFacts(rssFloor, rssPeak,
            heap.heapUsedMi(), heap.heapCommittedMi(), heap.gcName(),
            effectiveCpu, startup, snap.restarts(), snap.uptimeSeconds(), requestRate,
            heap.maxHeapMi(), heap.initialHeapMi(), cpuP95, throttled, latencyMean, latencyMax,
            snap.lastTerminationReason());

        ProfileFacts profile = pyroscope.summarize(service, from.toString(), to.toString(), 15);

        logger.info("facts collected service={} window={}m workload={} rss=[{},{}] startup={} samples={}",
            service, mins, workload != null, rssFloor, rssPeak, startup, profile.samples());
        return new Facts(workload, runtime, profile, null, ring);
    }

    /**
     * Startup of the slowest CURRENT pod (application.ready.time keyed by pod). Falls back to
     * the fleet max when the per-pod series carry no matching pod label.
     */
    private Double currentStartup(String service, java.util.List<String> readyPods) {
        if (readyPods != null && !readyPods.isEmpty()) {
            var perPod = prometheus.perPodStartup(service);
            var current = perPod.entrySet().stream()
                .filter(e -> readyPods.contains(e.getKey()))
                .mapToDouble(java.util.Map.Entry::getValue).max();
            if (current.isPresent()) {
                return current.getAsDouble();
            }
        }
        return prometheus.startupSeconds(service);
    }
}
