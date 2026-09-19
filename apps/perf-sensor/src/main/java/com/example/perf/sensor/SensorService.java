package com.example.perf.sensor;

import com.example.perf.sensor.collect.DumpCollector;
import com.example.perf.sensor.collect.FactsCollector;
import com.example.perf.sensor.collect.K8sCollector;
import com.example.perf.sensor.collect.LogCollector;
import com.example.perf.sensor.collect.PrometheusClient;
import com.example.perf.sensor.collect.PyroscopeClient;
import com.example.perf.sensor.facts.Facts;
import com.example.perf.sensor.facts.ProfileFacts;
import com.example.perf.sensor.facts.RuntimeFacts;
import com.example.perf.sensor.facts.ThreadFacts;
import com.example.perf.sensor.facts.WorkloadFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;

/**
 * The deterministic measurement engine behind the MCP tools and the REST API.
 * No LLM, no AWS SDK. The one computation it owns is {@link #sizeMemory}: exact
 * memory-sizing arithmetic plus a warm/load guard that must not be skipped. The
 * sizing NUMBERS (factors, thresholds) are supplied by the caller (the skill) —
 * this class owns only the arithmetic and the guard.
 */
@Service
public class SensorService {

    private static final Logger logger = LoggerFactory.getLogger(SensorService.class);

    private final FactsCollector facts;
    private final K8sCollector k8s;
    private final PrometheusClient prometheus;
    private final PyroscopeClient pyroscope;
    private final DumpCollector dump;
    private final LogCollector logs;

    public SensorService(FactsCollector facts, K8sCollector k8s, PrometheusClient prometheus,
                         PyroscopeClient pyroscope, DumpCollector dump, LogCollector logs) {
        this.facts = facts;
        this.k8s = k8s;
        this.prometheus = prometheus;
        this.pyroscope = pyroscope;
        this.dump = dump;
        this.logs = logs;
    }

    // --- records returned by the tools/endpoints -------------------------------

    /** Look-back window context for a measurement. */
    public record Window(Double uptimeSeconds, long samples, Double requestRatePerSec) {}

    /** Per-pod drill-down behind the fleet aggregate. */
    public record PodBreakdown(String pod, Double rssPeakMi, Double startupSeconds) {}

    /** All fact groups the checklist needs, plus the window and per-pod breakdown. */
    public record MeasureResult(String service, int windowMinutes,
                                WorkloadFacts workload, RuntimeFacts runtime,
                                ProfileFacts profile, Window window,
                                java.util.List<PodBreakdown> pods) {}

    /** Caller-supplied sizing policy — all required, no defaults (the skill owns the numbers). */
    public record SizeParams(double floorFactor, double peakFactor, double floorSafetyFactor,
                             int roundMi, int warmSeconds, int minSamples,
                             double minRequestRate, double minDeltaMi) {}

    public record Sized(String memory) {}

    public record SizeEvidence(Double rssFloorMi, Double rssPeakMi,
                               Double heapCommittedMi, Double cpuLimitCores) {}

    /** OK: computed sizing. BLOCKED: reason set, sizing null (guard not satisfied). */
    public record SizeResult(String status, String reason, Sized requests, Sized limits,
                             Integer maxRamPercentage, String gc,
                             SizeEvidence evidence, SizeParams params) {}

    public record ProfileTop(java.util.List<com.example.perf.sensor.facts.Frame> frames,
                             Double jitShare, Double gcShare, Double futexWallShare, long samples) {}

    public record StartupResult(String pod, String line, Double seconds, String kind) {}

    // --- measure ---------------------------------------------------------------

    public MeasureResult measure(String service, int windowMinutes) {
        var f = facts.collect(service, windowMinutes);
        var rt = f.runtime();
        var window = new Window(
            rt == null ? null : rt.uptimeSeconds(),
            f.profile() == null ? 0 : f.profile().samples(),
            rt == null ? null : rt.requestRatePerSec());
        return new MeasureResult(service, norm(windowMinutes), f.workload(), rt, f.profile(), window,
            perPodBreakdown(service, norm(windowMinutes)));
    }

    /** Per-pod peak + startup behind the fleet aggregate (best-effort; empty if no Prometheus). */
    private java.util.List<PodBreakdown> perPodBreakdown(String service, int windowMinutes) {
        if (prometheus == null) {
            return java.util.List.of();
        }
        var peak = prometheus.perPodPeakMi(service, service, windowMinutes);
        var startup = prometheus.perPodStartup(service);
        var pods = new java.util.LinkedHashSet<String>();
        pods.addAll(peak.keySet());
        pods.addAll(startup.keySet());
        return pods.stream()
            .map(p -> new PodBreakdown(p, peak.get(p), startup.get(p)))
            .toList();
    }

    // --- sizeMemory (arithmetic + guard) ---------------------------------------

    /** Collect facts and size. */
    public SizeResult sizeMemory(String service, int windowMinutes, SizeParams p) {
        return sizeMemory(facts.collect(service, windowMinutes), p);
    }

    /**
     * Pure sizing over already-collected facts (also the unit-test entry point).
     * Guard: BLOCKED unless {@code uptime > warmSeconds && samples > minSamples}
     * and {@code (requestRate > minRequestRate || rssPeak - rssFloor > minDeltaMi)}.
     * Rule: requests = roundUpMi(floor*floorFactor); limits =
     * roundUpMi(max(peak*peakFactor, floor*floorSafetyFactor)); maxRamPercentage = 75;
     * gc = cpuLimit <= 1 ? SerialGC : G1GC.
     */
    public SizeResult sizeMemory(Facts f, SizeParams p) {
        var rt = f.runtime();
        var wl = f.workload();
        Double floor = rt == null ? null : rt.rssFloorMi();
        Double peak = rt == null ? null : rt.rssPeakMi();
        Double cpuLimit = wl == null ? null : wl.cpuLimitCores();
        Double uptime = rt == null ? null : rt.uptimeSeconds();
        Double reqRate = rt == null ? null : rt.requestRatePerSec();
        Double heapCommitted = rt == null ? null : rt.heapCommittedMi();
        long samples = f.profile() == null ? 0 : f.profile().samples();
        var evidence = new SizeEvidence(floor, peak, heapCommitted, cpuLimit);

        if (floor == null || peak == null) {
            return blocked("insufficient measurement: missing working-set floor/peak from Prometheus",
                evidence, p);
        }
        boolean warm = uptime != null && uptime > p.warmSeconds() && samples > p.minSamples();
        if (!warm) {
            return blocked(("profiling window not warm: uptime=%s (need > %ds), samples=%d (need > %d). "
                + "Run a load phase after (re)start and retry.")
                .formatted(fmt(uptime), p.warmSeconds(), samples, p.minSamples()), evidence, p);
        }
        boolean load = (reqRate != null && reqRate > p.minRequestRate())
            || (peak - floor > p.minDeltaMi());
        if (!load) {
            return blocked(("no load observed: requestRate=%s rps (need > %s) and peak-floor=%.0f MiB "
                + "(need > %.0f). Drive traffic and retry.")
                .formatted(fmt(reqRate), fmt(p.minRequestRate()), peak - floor, p.minDeltaMi()), evidence, p);
        }

        String requests = roundUpMi(floor * p.floorFactor(), p.roundMi());
        String limits = roundUpMi(Math.max(peak * p.peakFactor(), floor * p.floorSafetyFactor()), p.roundMi());
        String gc = (cpuLimit != null && cpuLimit <= 1) ? "SerialGC" : "G1GC";
        logger.info("sizeMemory OK floor={} peak={} cpuLimit={} -> requests={} limits={} gc={}",
            floor, peak, cpuLimit, requests, limits, gc);
        return new SizeResult("OK", null, new Sized(requests), new Sized(limits), 75, gc, evidence, p);
    }

    private static SizeResult blocked(String reason, SizeEvidence ev, SizeParams p) {
        return new SizeResult("BLOCKED", reason, null, null, null, null, ev, p);
    }

    // --- threadDump / profileTop / startupLog ----------------------------------

    /** Thread dump across up to {@code sampleN} Ready pods, aggregated. sampleN<=1 = newest pod only. */
    public ThreadFacts threadDump(String service, int sampleN) {
        var refs = k8s.readyPodRefs(service, service);
        if (refs.isEmpty()) {
            var snap = k8s.collect(service, service);   // fallback to the representative pod
            return dump.threads(snap.appPodIP(), snap.appPodName());
        }
        int n = Math.max(1, Math.min(sampleN <= 0 ? 1 : sampleN, refs.size()));
        var dumps = refs.stream().limit(n)
            .map(r -> dump.threads(r.ip(), r.name()))
            .filter(java.util.Objects::nonNull)
            .toList();
        if (dumps.isEmpty()) {
            return null;
        }
        if (dumps.size() == 1) {
            return dumps.getFirst();
        }
        // Aggregate across the sampled pods: sum counts, merge states + blocking frames.
        var byState = new java.util.LinkedHashMap<String, Integer>();
        var frames = new java.util.LinkedHashMap<String, Integer>();
        int total = 0, virtual = 0, blocked = 0, pool = 0;
        for (var d : dumps) {
            total += d.total();
            virtual += d.virtualThreads();
            blocked += d.requestThreadsBlockedInFutureGet();
            pool += d.carriersParkedInPoolWait();
            if (d.byState() != null) {
                d.byState().forEach((k, v) -> byState.merge(k, v, Integer::sum));
            }
            if (d.topBlockingFrames() != null) {
                d.topBlockingFrames().forEach(f -> frames.merge(f.frame(), f.count(), Integer::sum));
            }
        }
        var topFrames = frames.entrySet().stream()
            .sorted(java.util.Map.Entry.<String, Integer>comparingByValue().reversed())
            .map(e -> new ThreadFacts.FrameCount(e.getKey(), e.getValue()))
            .toList();
        var pods = dumps.stream().map(ThreadFacts::pod).toList();
        return new ThreadFacts(String.join(",", pods), Instant.now().toString(),
            total, byState, virtual, blocked, pool, topFrames, dumps.getFirst().sample());
    }

    public ProfileTop profileTop(String service, String type, int windowMinutes, int limit) {
        var to = Instant.now();
        var from = to.minus(Duration.ofMinutes(norm(windowMinutes)));
        var t = pyroscope.top(service, type, from.toString(), to.toString(), limit <= 0 ? 15 : limit);
        return new ProfileTop(t.frames(), t.jitShare(), t.gcShare(), t.futexWallShare(), t.samples());
    }

    public StartupResult startupLog(String service) {
        var snap = k8s.collect(service, service);
        var line = logs.lastStartup(service, snap.appPodName(), snap.appContainer() != null ? snap.appContainer() : service);
        if (line == null) {
            return new StartupResult(snap.appPodName(), null, null, null);
        }
        return new StartupResult(snap.appPodName(), line.line(), line.seconds(), line.kind());
    }

    // --- helpers ---------------------------------------------------------------

    /** Round a MiB value UP to the next multiple of stepMi, formatted as a K8s quantity. */
    static String roundUpMi(double mi, int stepMi) {
        long v = (long) Math.ceil(mi);
        long rounded = ((v + stepMi - 1) / stepMi) * stepMi;
        return rounded + "Mi";
    }

    private static int norm(int windowMinutes) {
        return windowMinutes <= 0 ? 15 : windowMinutes;
    }

    private static String fmt(Double v) {
        return v == null ? "n/a" : "%.2f".formatted(v);
    }
}
