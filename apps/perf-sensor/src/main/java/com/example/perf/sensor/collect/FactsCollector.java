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

    public FactsCollector(K8sCollector k8s, PrometheusClient prometheus,
                          PyroscopeClient pyroscope, DumpCollector dump) {
        this.k8s = k8s;
        this.prometheus = prometheus;
        this.pyroscope = pyroscope;
        this.dump = dump;
    }

    /** Collect workload + runtime + profile facts (no thread dump). */
    public Facts collect(String service, int windowMinutes) {
        var mins = windowMinutes <= 0 ? 15 : windowMinutes;
        var to = Instant.now();
        var from = to.minus(Duration.ofMinutes(mins));

        var snap = k8s.collect(service, service);
        WorkloadFacts workload = snap.workload();
        String container = snap.appContainer() != null ? snap.appContainer() : service;

        Double rssFloor = prometheus.workingSetFloorMi(service, container, mins);
        Double rssPeak = prometheus.workingSetPeakMi(service, container, mins);
        Double startup = prometheus.startupSeconds(service);
        Double requestRate = prometheus.requestRatePerSec(service, mins);
        Double cpuP95 = prometheus.cpuUsageP95Cores(service, container, mins);
        Double throttled = prometheus.cpuThrottledRatio(service, container, mins);
        Double hikariPending = prometheus.hikariPendingMax(service, mins);
        var heap = dump.heap(snap.appPodIP());
        // effectiveCpuCount: the JVM rounds the CPU limit up to whole processors.
        Integer effectiveCpu = (workload != null && workload.cpuLimitCores() != null)
            ? (int) Math.ceil(workload.cpuLimitCores()) : null;
        var runtime = new RuntimeFacts(rssFloor, rssPeak,
            heap.heapUsedMi(), heap.heapCommittedMi(), heap.gcName(),
            effectiveCpu, startup, snap.restarts(), snap.uptimeSeconds(), requestRate,
            heap.maxHeapMi(), heap.initialHeapMi(), cpuP95, throttled, hikariPending,
            snap.lastTerminationReason());

        ProfileFacts profile = pyroscope.summarize(service, from.toString(), to.toString(), 15);

        logger.info("facts collected service={} window={}m workload={} rss=[{},{}] startup={} samples={}",
            service, mins, workload != null, rssFloor, rssPeak, startup, profile.samples());
        return new Facts(workload, runtime, profile, null);
    }
}
