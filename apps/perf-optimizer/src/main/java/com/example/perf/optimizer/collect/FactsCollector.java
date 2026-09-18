package com.example.perf.optimizer.collect;

import com.example.perf.optimizer.PrometheusTool;
import com.example.perf.optimizer.facts.Facts;
import com.example.perf.optimizer.facts.ProfileFacts;
import com.example.perf.optimizer.facts.RuntimeFacts;
import com.example.perf.optimizer.facts.WorkloadFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/**
 * Orchestrates all collectors into one {@link Facts} for a service over a window.
 * In this workshop the Pyroscope {@code service_name}, the Kubernetes Deployment
 * name, the namespace and the app container name are all the same string; a
 * separate namespace can be supplied for the general case. Every collector
 * degrades to nulls independently, so partial environments still analyze.
 */
@Component
public class FactsCollector {

    private static final Logger logger = LoggerFactory.getLogger(FactsCollector.class);

    private final K8sCollector k8s;
    private final PrometheusTool prometheus;
    private final PyroscopeCollector pyroscope;
    private final DumpCollector dump;

    public FactsCollector(K8sCollector k8s, PrometheusTool prometheus,
                          PyroscopeCollector pyroscope, DumpCollector dump) {
        this.k8s = k8s;
        this.prometheus = prometheus;
        this.pyroscope = pyroscope;
        this.dump = dump;
    }

    public Facts collect(String service, int windowMinutes) {
        return collect(service, service, windowMinutes);
    }

    public Facts collect(String service, String namespace, int windowMinutes) {
        var mins = windowMinutes <= 0 ? 15 : windowMinutes;
        var to = Instant.now();
        var from = to.minus(Duration.ofMinutes(mins));

        var snap = k8s.collect(namespace, service);
        WorkloadFacts workload = snap.workload();
        String container = snap.appContainer() != null ? snap.appContainer() : service;

        // Runtime facts: memory + startup (Prometheus), heap/gc (sidecar /dump), restarts (K8s).
        Double rssFloor = prometheus.workingSetFloorMi(namespace, container, mins);
        Double rssPeak = prometheus.workingSetPeakMi(namespace, container, mins);
        Double startup = prometheus.startupSeconds(service);
        Double requestRate = prometheus.requestRatePerSec(service, mins);
        var heap = dump.heap(snap.appPodIP());
        // effectiveCpuCount: the JVM rounds the CPU limit up to whole processors.
        Integer effectiveCpu = (workload != null && workload.cpuLimitCores() != null)
            ? (int) Math.ceil(workload.cpuLimitCores()) : null;
        var runtime = new RuntimeFacts(rssFloor, rssPeak,
            heap == null ? null : heap.heapUsedMi(),
            heap == null ? null : heap.heapCommittedMi(),
            heap == null ? null : heap.gcName(),
            effectiveCpu, startup, snap.restarts(), snap.uptimeSeconds(), requestRate);

        ProfileFacts profile = pyroscope.collect(service, from.toString(), to.toString(), 25);
        var threads = dump.threads(snap.appPodIP());

        logger.info("facts collected service={} ns={} window={}m workload={} rss=[{},{}] startup={} samples={} threads={}",
            service, namespace, mins, workload != null, rssFloor, rssPeak, startup,
            profile == null ? 0 : profile.samples(), threads != null);
        return new Facts(workload, runtime, profile, threads);
    }
}
