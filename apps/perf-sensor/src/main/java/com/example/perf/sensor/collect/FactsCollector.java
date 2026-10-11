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
    /**
     * Shortest steady window that CPU and throttling are reported over; younger pods report null.
     * Four 15 s scrapes: over two, a cAdvisor rate is noisy or empty.
     */
    static final int MIN_STEADY_SECONDS = 60;

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
        if (snap.readyPodNames() != null && snap.readyPodNames().isEmpty()) {
            // The API answered and no pod is Ready: there is no current JVM to measure. A query
            // without the pod matcher would read pods that are gone.
            logger.info("facts collected service={}: no Ready pod, runtime facts unavailable", service);
            return new Facts(workload, null, null, null);
        }
        String container = snap.appContainer() != null ? snap.appContainer() : service;
        // Scope cAdvisor facts to the pods that exist NOW: a pod replaced by a rollout earlier
        // in the window must not supply the peak, the steady CPU or the startup of the current one.
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
        Double startup = currentStartup(service, snap.readyPodNames());   // pods null: API unavailable
        var heap = dump.heap(snap.appPodIP());
        var ring = jfr.collect(snap.appPodIP(), snap.appPodName());
        // Traffic facts (Micrometer, fleet-wide) over the window clipped to the current pod's
        // lifetime, so a pod that has seen no load yet does not inherit the previous pod's traffic.
        int trafficMins = uptime == null ? mins : (int) Math.max(1, Math.min(mins, Math.floor(uptime / 60.0)));
        Double requestRate = prometheus.requestRatePerSec(service, pods, trafficMins);
        // Latency describes steady state: exclude the boot minute once the pod has one, so the
        // first slow requests do not fail the latency bar. Younger pods use the lifetime window.
        int latencyMins = steadyMins > 0 ? steadyMins : trafficMins;
        Double latencyMean = prometheus.latencyMeanMs(service, pods, latencyMins);
        Double latencyMax = prometheus.latencyMaxMs(service, pods, latencyMins);
        // CPU and throttling describe steady state: the window starts after readiness and after
        // the JIT stopped dominating, so boot CPU never sizes the request. Within 2 min of a
        // restart the JIT is still compiling, so the steady CPU is the window's mean minus the
        // compiler threads' share of the CPU profile over the same window: compilation ends, the
        // load's CPU stays. A pod measured later has less JIT to subtract and reads the same.
        // Per pod (the mean and the JIT share of the same pod), then the worst pod.
        Double steadyStart = steadyStartSeconds(uptime, startup, ring, to);
        Integer steadySecs = null;
        SteadyCpu cpu = SteadyCpu.NONE;
        Double throttled = null;
        if (steadyStart != null) {
            steadySecs = (int) Math.min(mins * 60L, Math.floor(uptime - steadyStart));
            cpu = steadyCpu(service, container, pods, steadySecs, to);
            throttled = prometheus.cpuThrottledRatio(service, container, pods, Math.min(300, steadySecs));
        } else if (uptime == null) {
            // No pod age (Kubernetes API unavailable): the requested window, boot included.
            cpu = steadyCpu(service, container, pods, mins * 60, to);
        }
        // effectiveCpuCount: what the JVM itself reported (jdk.ContainerConfiguration); null
        // without the ring. The limit is not a stand-in: item 5 compares the two.
        Integer effectiveCpu = ring != null && ring.container() != null ? ring.container().effectiveCpuCount() : null;
        var runtime = new RuntimeFacts(floor, peak,
            heap.heapUsedMi(), heap.heapCommittedMi(), heap.gcName(),
            effectiveCpu, startup, snap.restarts(), uptime, requestRate,
            heap.maxHeapMi(), heap.initialHeapMi(), cpu.steadyCores(), cpu.meanCores(), cpu.jitShare(), steadyStart, steadySecs,
            throttled, latencyMean, latencyMax,
            snap.lastTerminationReason());

        ProfileFacts profile = pyroscope.summarize(service, pods, from.toString(), to.toString(), 15);

        logger.info("facts collected service={} window={}m workload={} workingSet=[{},{}] startup={} steady={}s from {}s cpu={} (pod {}, jit {}%) samples={}",
            service, mins, workload != null, floor, peak, startup, steadySecs, steadyStart, cpu.steadyCores(), cpu.pod(),
            cpu.jitShare(), profile.samples());
        return new Facts(workload, runtime, profile, ring);
    }

    /** The worst pod's steady CPU: its mean, its own JIT share, and the mean without that share. */
    record SteadyCpu(String pod, Double meanCores, Double jitShare, Double steadyCores) {
        static final SteadyCpu NONE = new SteadyCpu(null, null, null, null);
    }

    /**
     * Per pod over the last {@code seconds}: mean CPU (cAdvisor) minus that pod's JIT share
     * (Pyroscope, same window); the pod with the highest result. A fleet JIT share subtracted
     * from the busiest pod would mix pods: one that only compiles would lower another's load.
     */
    SteadyCpu steadyCpu(String service, String container, String podRegex, int seconds, Instant to) {
        var from = to.minusSeconds(seconds).toString();
        SteadyCpu worst = SteadyCpu.NONE;
        for (var e : prometheus.cpuUsageMeanCoresByPod(service, container, podRegex, seconds).entrySet()) {
            Double jit = pyroscope.cpuJitShare(service, e.getKey(), from, to.toString());
            Double steady = withoutJit(e.getValue(), jit);
            if (worst.steadyCores() == null || steady > worst.steadyCores()) {
                worst = new SteadyCpu(e.getKey(), e.getValue(), jit, steady);
            }
        }
        return worst;
    }

    /** Mean CPU minus the JIT's percent share; the mean as it is when no profile covers the window. */
    static Double withoutJit(Double cpuMean, Double jitSharePct) {
        if (cpuMean == null) {
            return null;
        }
        if (jitSharePct == null) {
            return cpuMean;
        }
        double share = Math.max(0, Math.min(jitSharePct, 100.0)) / 100.0;
        return Math.round(cpuMean * (1 - share) * 1000.0) / 1000.0;
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
     * Startup of the slowest CURRENT pod, resolved per pod: the sensor's own log-derived gauge
     * (Started/Restored line — the only source that is right for a CRaC restore), else that
     * pod's application.ready.time. null while any Ready pod has neither (a maximum over part
     * of the pods could miss the slowest). The fleet max only when the Ready set is unknown.
     */
    Double currentStartup(String service, List<String> readyPods) {
        if (readyPods == null) {
            return prometheus.startupSeconds(service);
        }
        if (readyPods.isEmpty()) {
            return null;
        }
        var perPod = perPodStartup(service, readyPods);
        if (perPod.size() < readyPods.size()) {
            return null;
        }
        return perPod.values().stream().mapToDouble(Double::doubleValue).max().orElseThrow();
    }

    /** Per-pod startup, log gauge else application.ready.time, for the given pods (pods without either are absent). */
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
