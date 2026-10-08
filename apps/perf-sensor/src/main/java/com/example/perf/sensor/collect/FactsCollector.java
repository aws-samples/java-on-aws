package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.Facts;
import com.example.perf.sensor.facts.JfrFacts;
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
    /** Seconds after container start that are boot ramp, excluded from the floor and latency windows. */
    static final int BOOT_SECONDS = 60;
    /** Margin after readiness before CPU counts as steady (first requests, pool warm-up). */
    static final int READY_MARGIN_SECONDS = 10;
    /** Shortest steady window that CPU and throttling are reported over; younger pods report null. */
    static final int MIN_STEADY_SECONDS = 30;
    /** 15 s points the p95 range needs; with fewer, the steady CPU is the mean over the window. */
    static final int MIN_P95_POINTS = 8;
    private static final int P95_STEP_SECONDS = 15;
    /** Look-back of each p95 point (rate window), kept inside the steady window. */
    private static final int RATE_SECONDS = 60;

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
        // steadyMins is that same post-boot window; -1 means the pod is too young to have one.
        int steadyMins = -1;
        Double floor = null;
        if (uptime != null && uptime >= BOOT_SECONDS + 60) {
            steadyMins = (int) Math.min(mins, Math.floor((uptime - BOOT_SECONDS) / 60.0));
            floor = prometheus.workingSetFloorMi(service, container, pods, steadyMins);
        } else if (uptime == null) {
            floor = prometheus.workingSetFloorMi(service, container, pods, mins);
        }
        Double peak = prometheus.workingSetPeakMi(service, container, pods, mins);
        Double startup = currentStartup(service, snap.readyPodNames());
        var heap = dump.heap(snap.appPodIP());
        var ring = jfr.collect(snap.appPodIP(), snap.appPodName());
        // Traffic facts (Micrometer, fleet-wide) over the window clipped to the current pod's
        // lifetime, so a pod that has seen no load yet does not inherit the previous pod's traffic.
        int trafficMins = uptime == null ? mins : (int) Math.max(1, Math.min(mins, Math.floor(uptime / 60.0)));
        Double requestRate = prometheus.requestRatePerSec(service, trafficMins);
        // Latency describes steady state: exclude the boot minute once the pod has one, so the
        // first slow requests do not fail the latency bar. Younger pods use the lifetime window.
        int latencyMins = steadyMins > 0 ? steadyMins : trafficMins;
        Double latencyMean = prometheus.latencyMeanMs(service, latencyMins);
        Double latencyMax = prometheus.latencyMaxMs(service, latencyMins);
        // CPU and throttling describe steady state: the window starts after readiness and after
        // the JIT stopped dominating, and every rate look-back stays inside it, so boot CPU never
        // sizes the request. A short window (a freshly rolled pod) reports the mean, not a p95
        // of two or three points.
        Double steadyStart = steadyStartSeconds(uptime, startup, ring, to);
        Integer steadySecs = null;
        Double cpuSteady = null;
        String cpuStatistic = null;
        Double throttled = null;
        if (steadyStart != null) {
            steadySecs = (int) Math.min(mins * 60L, Math.floor(uptime - steadyStart));
            int p95Range = steadySecs - RATE_SECONDS;
            if (p95Range >= (MIN_P95_POINTS - 1) * P95_STEP_SECONDS) {
                cpuSteady = prometheus.cpuUsageP95Cores(service, container, pods, p95Range);
                cpuStatistic = "p95";
            } else {
                cpuSteady = prometheus.cpuUsageMeanCores(service, container, pods, steadySecs);
                cpuStatistic = "mean";
            }
            throttled = prometheus.cpuThrottledRatio(service, container, pods, Math.min(300, steadySecs));
        } else if (uptime == null) {
            // No pod age (Kubernetes API unavailable): the requested window, boot included.
            cpuSteady = prometheus.cpuUsageP95Cores(service, container, pods, mins * 60 - RATE_SECONDS);
            cpuStatistic = cpuSteady == null ? null : "p95";
        }
        if (cpuSteady == null) {
            cpuStatistic = null;
        }
        // effectiveCpuCount: what the JVM itself reported (jdk.ContainerConfiguration) when the
        // ring is available; otherwise the CPU limit rounded up to whole processors.
        Integer effectiveCpu = ring != null && ring.container() != null && ring.container().effectiveCpuCount() != null
            ? ring.container().effectiveCpuCount()
            : (workload != null && workload.cpuLimitCores() != null) ? (int) Math.ceil(workload.cpuLimitCores()) : null;
        var runtime = new RuntimeFacts(floor, peak,
            heap.heapUsedMi(), heap.heapCommittedMi(), heap.gcName(),
            effectiveCpu, startup, snap.restarts(), uptime, requestRate,
            heap.maxHeapMi(), heap.initialHeapMi(), cpuSteady, cpuStatistic, steadyStart, steadySecs,
            throttled, latencyMean, latencyMax,
            snap.lastTerminationReason());

        ProfileFacts profile = pyroscope.summarize(service, from.toString(), to.toString(), 15);

        logger.info("facts collected service={} window={}m workload={} workingSet=[{},{}] startup={} steady={}s from {}s cpu={} {} samples={}",
            service, mins, workload != null, floor, peak, startup, steadySecs, steadyStart, cpuStatistic, cpuSteady,
            profile.samples());
        return new Facts(workload, runtime, profile, ring);
    }

    /**
     * Pod age, seconds, at which steady state starts: readiness ({@code startup}, else the boot
     * minute) plus a margin, or the end of the last busy JIT interval from the JFR ring if later.
     * Clamped so the steady window is at least {@link #MIN_STEADY_SECONDS}; null when the pod is
     * not yet that far past readiness, or its age is unknown.
     */
    static Double steadyStartSeconds(Double uptime, Double startup, JfrFacts ring, Instant now) {
        if (uptime == null) {
            return null;
        }
        double ready = (startup == null ? BOOT_SECONDS : startup) + READY_MARGIN_SECONDS;
        double latest = uptime - MIN_STEADY_SECONDS;
        if (latest < ready) {
            return null;
        }
        double start = ready;
        Double jit = jitSettledSeconds(uptime, ring, now);
        if (jit != null) {
            start = Math.max(start, jit);
        }
        return Math.min(start, latest);
    }

    /** Pod age at which the JIT stopped being busy (JFR {@code compilation.busyUntil}), or null. */
    static Double jitSettledSeconds(double uptime, JfrFacts ring, Instant now) {
        if (ring == null || ring.compilation() == null || ring.compilation().busyUntil() == null) {
            return null;
        }
        var containerStart = now.minusMillis((long) (uptime * 1000));
        double s = Duration.between(containerStart, Instant.parse(ring.compilation().busyUntil())).toMillis() / 1000.0;
        return s < 0 ? null : s;
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
