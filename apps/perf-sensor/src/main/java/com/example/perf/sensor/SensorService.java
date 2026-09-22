package com.example.perf.sensor;

import com.example.perf.sensor.collect.DumpCollector;
import com.example.perf.sensor.collect.FactsCollector;
import com.example.perf.sensor.collect.JfrCollector;
import com.example.perf.sensor.collect.K8sCollector;
import com.example.perf.sensor.collect.LogCollector;
import com.example.perf.sensor.collect.PrometheusClient;
import com.example.perf.sensor.collect.PyroscopeClient;
import com.example.perf.sensor.facts.Facts;
import com.example.perf.sensor.facts.JfrFacts;
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
    private final JfrCollector jfr;

    public SensorService(FactsCollector facts, K8sCollector k8s, PrometheusClient prometheus,
                         PyroscopeClient pyroscope, DumpCollector dump, LogCollector logs,
                         JfrCollector jfr) {
        this.facts = facts;
        this.k8s = k8s;
        this.prometheus = prometheus;
        this.pyroscope = pyroscope;
        this.dump = dump;
        this.logs = logs;
        this.jfr = jfr;
    }

    // --- records returned by the tools/endpoints -------------------------------

    /** Look-back window context for a measurement. */
    public record Window(Double uptimeSeconds, long samples, Double requestRatePerSec) {}

    /** Per-pod drill-down behind the fleet aggregate. */
    public record PodBreakdown(String pod, Double rssPeakMi, Double startupSeconds) {}

    /** All fact groups the checklist needs, plus the JFR ring, the window and per-pod breakdown. */
    public record MeasureResult(String service, int windowMinutes,
                                WorkloadFacts workload, RuntimeFacts runtime,
                                ProfileFacts profile, JfrFacts jfr, Window window,
                                java.util.List<PodBreakdown> pods) {}

    /** Caller-supplied sizing policy — all required, no defaults (the skill owns the numbers). */
    public record SizeParams(double peakFactor, double floorSafetyFactor,
                             int roundMi, int warmSeconds, int minSamples,
                             double minRequestRate, double minDeltaMi) {}

    public record Sized(String memory) {}

    public record SizeEvidence(Double rssFloorMi, Double rssPeakMi,
                               Double heapCommittedMi, Double cpuLimitCores) {}

    /**
     * OK: computed sizing — requests == limits (Guaranteed memory QoS: JVM memory is stable
     * after warm-up and a Burstable JVM is the first OOM-kill candidate on a busy node).
     * BLOCKED: reason set, sizing null (guard not satisfied).
     */
    public record SizeResult(String status, String reason, Sized requests, Sized limits,
                             Integer maxRamPercentage, Integer initialRamPercentage, String gc,
                             SizeEvidence evidence, SizeParams params) {}

    public record ProfileTop(java.util.List<com.example.perf.sensor.facts.Frame> frames,
                             Double jitShare, Double gcShare, Double futexWallShare, long samples) {}

    public record StartupResult(String pod, String line, Double seconds, String kind) {}

    // --- measure ---------------------------------------------------------------

    public MeasureResult measure(String service, int windowMinutes) {
        return measure(service, windowMinutes, 0);
    }

    /**
     * {@code minUptimeSeconds}: a freshly rolled pod has no peak, p95 or throttle share yet (the
     * load-guarded checklist items need ~2 min of traffic on THAT pod). When the current pod is
     * younger, wait until it reaches this age (at most 120 s) before collecting, so a question
     * asked right after a rollout settles instead of returning UNKNOWNs.
     */
    public MeasureResult measure(String service, int windowMinutes, int minUptimeSeconds) {
        if (minUptimeSeconds > 0) {
            var snap = k8s.collect(service, service);
            if (snap.uptimeSeconds() != null && snap.uptimeSeconds() < minUptimeSeconds) {
                long waitMs = Math.min(120, minUptimeSeconds - snap.uptimeSeconds().longValue()) * 1000L;
                logger.info("measure service={} pod={} is {}s old, waiting {}s for minUptime {}s",
                    service, snap.appPodName(), snap.uptimeSeconds().intValue(), waitMs / 1000, minUptimeSeconds);
                try {
                    Thread.sleep(waitMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
        }
        var f = facts.collect(service, windowMinutes);
        var rt = f.runtime();
        var window = new Window(
            rt == null ? null : rt.uptimeSeconds(),
            f.profile() == null ? 0 : f.profile().samples(),
            rt == null ? null : rt.requestRatePerSec());
        return new MeasureResult(service, norm(windowMinutes), f.workload(), rt, f.profile(), f.jfr(), window,
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
     * Rule: limits = roundUpMi(max(peak*peakFactor, floor*floorSafetyFactor));
     * requests = limits (Guaranteed); maxRamPercentage = 75; initialRamPercentage = 50;
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

        String limits = roundUpMi(Math.max(peak * p.peakFactor(), floor * p.floorSafetyFactor()), p.roundMi());
        String requests = limits;   // Guaranteed memory QoS
        String gc = (cpuLimit != null && cpuLimit <= 1) ? "SerialGC" : "G1GC";
        logger.info("sizeMemory OK floor={} peak={} cpuLimit={} -> requests=limits={} gc={}",
            floor, peak, cpuLimit, limits, gc);
        return new SizeResult("OK", null, new Sized(requests), new Sized(limits), 75, 50, gc, evidence, p);
    }

    private static SizeResult blocked(String reason, SizeEvidence ev, SizeParams p) {
        return new SizeResult("BLOCKED", reason, null, null, null, null, null, ev, p);
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
        int total = 0, virtual = 0, active = 0, blocked = 0, pool = 0, inTx = 0;
        for (var d : dumps) {
            total += d.total();
            virtual += d.virtualThreads();
            active += d.requestThreadsActive();
            blocked += d.requestThreadsBlockedInFutureGet();
            pool += d.carriersParkedInPoolWait();
            inTx += d.blockedInsideTransaction();
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
            total, byState, virtual, active, blocked, pool, inTx, topFrames, dumps.getFirst().sample());
    }

    /**
     * Sample the representative pod's thread dump {@code samples} times, {@code intervalMs} apart,
     * and aggregate over TIME. A request-path block on a virtual-thread app is brief — the vthread
     * parks in {@code Future.get()} only for the downstream round-trip — so a single snapshot
     * usually misses it. {@code requestThreadsBlockedInFutureGet} is the PEAK concurrent blocked
     * across samples; {@code topBlockingFrames} counts are summed. Must be taken WHILE load flows.
     */
    public ThreadFacts threadDumpOverTime(String service, int samples, long intervalMs) {
        int n = Math.max(1, Math.min(samples <= 0 ? 5 : samples, 30));
        long gap = intervalMs <= 0 ? 1000L : Math.min(intervalMs, 5000L);
        var snap = k8s.collect(service, service);
        String ip = snap.appPodIP(), name = snap.appPodName();
        var byState = new java.util.LinkedHashMap<String, Integer>();
        var frames = new java.util.LinkedHashMap<String, Integer>();
        int maxTotal = 0, maxVirtual = 0, maxActive = 0, maxBlocked = 0, maxPool = 0, maxInTx = 0, taken = 0;
        ThreadFacts last = null;
        for (int i = 0; i < n; i++) {
            var d = dump.threads(ip, name);
            if (d != null) {
                taken++;
                last = d;
                maxTotal = Math.max(maxTotal, d.total());
                maxVirtual = Math.max(maxVirtual, d.virtualThreads());
                maxActive = Math.max(maxActive, d.requestThreadsActive());
                maxBlocked = Math.max(maxBlocked, d.requestThreadsBlockedInFutureGet());
                maxPool = Math.max(maxPool, d.carriersParkedInPoolWait());
                maxInTx = Math.max(maxInTx, d.blockedInsideTransaction());
                if (d.byState() != null) {
                    d.byState().forEach((k, v) -> byState.merge(k, v, Integer::sum));
                }
                if (d.topBlockingFrames() != null) {
                    d.topBlockingFrames().forEach(f -> frames.merge(f.frame(), f.count(), Integer::sum));
                }
            }
            if (i < n - 1) {
                try {
                    Thread.sleep(gap);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        if (taken == 0) {
            return null;
        }
        var topFrames = frames.entrySet().stream()
            .sorted(java.util.Map.Entry.<String, Integer>comparingByValue().reversed())
            .map(e -> new ThreadFacts.FrameCount(e.getKey(), e.getValue()))
            .toList();
        return new ThreadFacts(name, Instant.now().toString(),
            maxTotal, byState, maxVirtual, maxActive, maxBlocked, maxPool, maxInTx, topFrames,
            last == null ? null : last.sample());
    }

    /**
     * A blocking diagnosis: thread facts sampled over time WHILE THE OPERATOR'S LOAD RUNS.
     * status OK, or BLOCKED (threads null) when no load is flowing right now.
     */
    public record BlockingDiagnosis(String status, String reason, ThreadFacts threads,
                                    int durationSec, Double requestRatePerSec) {}

    /**
     * Diagnose a request-path block by sampling the JSON thread dump over {@code durationSec}
     * seconds. The sensor drives NO traffic: a blocked request thread (Future.get on a virtual
     * thread) exists only while requests are in flight, and JFR does not record virtual-thread
     * parks, so the caller must have a load run going. Guard: BLOCKED unless the request rate
     * over the last minute exceeds {@code minRequestRate}. Read-only on any image, including CRaC.
     * Defaults 20 s at 500 ms = 40 dumps: a ~10 ms block at 50 rps is present in a given dump
     * with p ≈ 0.4, so 12 dumps missed it once in ~25 runs; 40 dumps make a miss negligible.
     */
    public BlockingDiagnosis diagnoseBlocking(String service, int durationSec, long intervalMs,
                                              double minRequestRate) {
        int dur = Math.max(3, Math.min(durationSec <= 0 ? 20 : durationSec, 60));
        long gap = intervalMs <= 0 ? 500L : Math.min(intervalMs, 5000L);
        int samples = Math.max(2, (int) ((dur * 1000L) / gap));
        Double rateNow = prometheus == null ? null : prometheus.requestRatePerSec(service, 1);
        if (rateNow == null || rateNow <= minRequestRate) {
            return new BlockingDiagnosis("BLOCKED",
                ("no load flowing now: requestRate(1m)=%s rps (need > %s). Start the load run, then retry "
                    + "while it is running.").formatted(fmt(rateNow), fmt(minRequestRate)),
                null, dur, rateNow);
        }
        return new BlockingDiagnosis("OK", null, threadDumpOverTime(service, samples, gap), dur, rateNow);
    }

    // --- sizeCpu (arithmetic + guard) ------------------------------------------

    /** Caller-supplied CPU sizing policy — all required (the skill owns the numbers). */
    public record CpuParams(double cpuFactor, int roundMillicores, int warmSeconds, int minSamples,
                            double minRequestRate, double minDeltaMi) {}

    public record CpuEvidence(Double cpuUsageP95Cores, Double cpuRequestCores, Double cpuLimitCores) {}

    /** OK: requests.cpu computed, limits.cpu = current (unchanged). BLOCKED: reason set. */
    public record CpuResult(String status, String reason, String requestsCpu, String limitsCpu,
                            CpuEvidence evidence, CpuParams params) {}

    public CpuResult sizeCpu(String service, int windowMinutes, CpuParams p) {
        return sizeCpu(facts.collect(service, windowMinutes), p);
    }

    /**
     * Pure CPU sizing over collected facts. Guard identical to sizeMemory (warm + load).
     * Rule: requests.cpu = roundUp(cpuUsageP95 * cpuFactor, roundMillicores); limits.cpu unchanged
     * — the boot spike is the startup boost's job, not the steady request's.
     */
    public CpuResult sizeCpu(Facts f, CpuParams p) {
        var rt = f.runtime();
        var wl = f.workload();
        Double p95 = rt == null ? null : rt.cpuUsageP95Cores();
        Double cpuReq = wl == null ? null : wl.cpuRequestCores();
        Double cpuLim = wl == null ? null : wl.cpuLimitCores();
        Double uptime = rt == null ? null : rt.uptimeSeconds();
        Double reqRate = rt == null ? null : rt.requestRatePerSec();
        Double floor = rt == null ? null : rt.rssFloorMi();
        Double peak = rt == null ? null : rt.rssPeakMi();
        long samples = f.profile() == null ? 0 : f.profile().samples();
        var evidence = new CpuEvidence(p95, cpuReq, cpuLim);

        if (p95 == null) {
            return new CpuResult("BLOCKED", "insufficient measurement: missing CPU usage p95 from Prometheus",
                null, null, evidence, p);
        }
        boolean warm = uptime != null && uptime > p.warmSeconds() && samples > p.minSamples();
        if (!warm) {
            return new CpuResult("BLOCKED", ("profiling window not warm: uptime=%s (need > %ds), samples=%d (need > %d). "
                + "Run a load phase after (re)start and retry.")
                .formatted(fmt(uptime), p.warmSeconds(), samples, p.minSamples()), null, null, evidence, p);
        }
        boolean load = (reqRate != null && reqRate > p.minRequestRate())
            || (floor != null && peak != null && peak - floor > p.minDeltaMi());
        if (!load) {
            return new CpuResult("BLOCKED", ("no load observed: requestRate=%s rps (need > %s). Drive traffic and retry.")
                .formatted(fmt(reqRate), fmt(p.minRequestRate())), null, null, evidence, p);
        }
        long millis = (long) Math.ceil(p95 * p.cpuFactor() * 1000.0);
        long rounded = ((millis + p.roundMillicores() - 1) / p.roundMillicores()) * p.roundMillicores();
        String requests = rounded + "m";
        String limits = cpuLim == null ? null : quantity(cpuLim);
        logger.info("sizeCpu OK p95={} -> requests={} limits={} (unchanged)", p95, requests, limits);
        return new CpuResult("OK", null, requests, limits, evidence, p);
    }

    /** Cores as a K8s quantity: whole cores as "1", fractions as millicores "500m". */
    static String quantity(double cores) {
        if (cores == Math.rint(cores)) {
            return String.valueOf((long) cores);
        }
        return Math.round(cores * 1000.0) + "m";
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
