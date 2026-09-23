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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Orchestrates the collectors into one {@link Facts} for a service over a window.
 * Contract: the Pyroscope {@code service_name}, the Deployment name, the namespace and
 * the app container name are the same string (see README). Every collector degrades to
 * nulls independently, so partial environments still measure. Thread facts are collected
 * separately (only when a dump is requested).
 */
@Component
public class FactsCollector {

    private static final Logger logger = LoggerFactory.getLogger(FactsCollector.class);
    /** Seconds after container start that are boot ramp, excluded from floor and throttle windows. */
    static final int BOOT_SECONDS = 60;

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

    /** Collect workload + runtime + profile + JFR facts (no thread dump) from a fresh K8s snapshot. */
    public Facts collect(String service, int windowMinutes) {
        return collect(service, windowMinutes, k8s.collect(service, service));
    }

    /** Same, over an already-taken K8s snapshot (avoids a second round of API reads). */
    public Facts collect(String service, int windowMinutes, K8sCollector.Snapshot snap) {
        var mins = windowMinutes <= 0 ? 15 : windowMinutes;
        var to = Instant.now();
        var from = to.minus(Duration.ofMinutes(mins));

        WorkloadFacts workload = snap.workload();
        String container = snap.appContainer() != null ? snap.appContainer() : service;
        // Scope cAdvisor facts to the pods that exist NOW: a pod replaced by a rollout earlier
        // in the window must not supply the peak, the p95 or the startup of the current one.
        String pods = snap.readyPodRegex();
        Double uptime = snap.uptimeSeconds();

        // Floor: the window clipped to the pod's lifetime minus its boot ramp (needs >= 1 min of
        // post-boot data, else null); the query itself takes a low quantile, not the minimum.
        Double floor = null;
        if (uptime != null && uptime >= BOOT_SECONDS + 60) {
            int floorMins = (int) Math.min(mins, Math.floor((uptime - BOOT_SECONDS) / 60.0));
            floor = prometheus.workingSetFloorMi(service, container, pods, floorMins);
        } else if (uptime == null) {
            floor = prometheus.workingSetFloorMi(service, container, pods, mins);
        }
        Double peak = prometheus.workingSetPeakMi(service, container, pods, mins);
        Double startup = currentStartup(service, snap.readyPodNames());
        // Traffic facts (Micrometer, fleet-wide) over the window clipped to the current pod's
        // lifetime, so a pod that has seen no load yet does not inherit the previous pod's traffic.
        int trafficMins = uptime == null ? mins : (int) Math.max(1, Math.min(mins, Math.floor(uptime / 60.0)));
        Double requestRate = prometheus.requestRatePerSec(service, trafficMins);
        Double cpuP95 = prometheus.cpuUsageP95Cores(service, container, pods, mins);
        // Throttling: the pod's lifetime minus its first 60 s (boot JIT saturates the quota by
        // design), capped at 5 min; needs at least 30 s of steady state, else null.
        Double throttled = null;
        if (uptime != null && uptime >= BOOT_SECONDS + 30) {
            int throttleSecs = (int) Math.min(mins * 60L, Math.min(300, uptime - BOOT_SECONDS));
            throttled = prometheus.cpuThrottledRatio(service, container, pods, throttleSecs);
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
        var runtime = new RuntimeFacts(floor, peak,
            heap.heapUsedMi(), heap.heapCommittedMi(), heap.gcName(),
            effectiveCpu, startup, snap.restarts(), uptime, requestRate,
            heap.maxHeapMi(), heap.initialHeapMi(), cpuP95, throttled, latencyMean, latencyMax,
            snap.lastTerminationReason());

        ProfileFacts profile = pyroscope.summarize(service, from.toString(), to.toString(), 15);

        logger.info("facts collected service={} window={}m workload={} workingSet=[{},{}] startup={} samples={}",
            service, mins, workload != null, floor, peak, startup, profile.samples());
        return new Facts(workload, runtime, profile, ring);
    }

    /**
     * Startup of the slowest CURRENT pod. Source order: the sensor's own log-derived gauge
     * (Started/Restored line of each pod — the only source that is right for a CRaC restore),
     * then application.ready.time per pod, then the fleet max.
     */
    Double currentStartup(String service, List<String> readyPods) {
        if (readyPods != null && !readyPods.isEmpty()) {
            for (var perPod : List.of(prometheus.perPodStartupFromLog(service), prometheus.perPodStartup(service))) {
                var current = perPod.entrySet().stream()
                    .filter(e -> readyPods.contains(e.getKey()))
                    .mapToDouble(Map.Entry::getValue).max();
                if (current.isPresent()) {
                    return current.getAsDouble();
                }
            }
        }
        return prometheus.startupSeconds(service);
    }

    /** Per-pod startup, same source order as {@link #currentStartup}, restricted to the given pods. */
    public Map<String, Double> perPodStartup(String service, List<String> readyPods) {
        var fromLog = prometheus.perPodStartupFromLog(service);
        var fromMetric = prometheus.perPodStartup(service);
        var out = new LinkedHashMap<String, Double>();
        for (var pod : readyPods) {
            Double s = fromLog.containsKey(pod) ? fromLog.get(pod) : fromMetric.get(pod);
            if (s != null) {
                out.put(pod, s);
            }
        }
        return out;
    }
}
