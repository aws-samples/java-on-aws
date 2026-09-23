package com.example.perf.sensor;

import com.example.perf.sensor.collect.DumpCollector;
import com.example.perf.sensor.collect.FactsCollector;
import com.example.perf.sensor.collect.K8sCollector;
import com.example.perf.sensor.collect.LogCollector;
import com.example.perf.sensor.collect.PrometheusClient;
import com.example.perf.sensor.collect.PyroscopeClient;
import com.example.perf.sensor.facts.Facts;
import com.example.perf.sensor.facts.Frame;
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
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.IntBinaryOperator;

/**
 * The deterministic measurement engine behind the MCP tools and the REST API. No LLM, no
 * AWS SDK. It owns the guards and the arithmetic — {@link #sizeMemory}, {@link #sizeCpu},
 * {@link #diagnoseBlocking} — and the aggregation of thread dumps over pods and over time.
 * The sizing NUMBERS (factors, thresholds) are supplied by the caller (the skill's
 * {@code sizing-policy.yaml}); this class owns only the arithmetic and the guards.
 */
@Service
public class SensorService {

    private static final Logger logger = LoggerFactory.getLogger(SensorService.class);
    private static final int DEFAULT_WINDOW_MINUTES = 15;
    private static final int MAX_SETTLE_SLICE_SECONDS = 30;

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

    /**
     * Look-back window context for a measurement. {@code waitedSeconds}: how long this call
     * waited for the pod to age (see measure's minUptimeSeconds). {@code settleRemainingSeconds}:
     * > 0 means the pod is still younger than requested — call again to keep waiting (each call
     * waits at most 30 s so the caller can report progress); 0 means the facts are settled.
     * {@code settleNote}: human-readable reason when the call did not wait (e.g. no load flowing).
     */
    public record Window(Double uptimeSeconds, long samples, Double requestRatePerSec,
                         Integer waitedSeconds, Integer settleRemainingSeconds, String settleNote) {}

    /** Per-pod drill-down behind the fleet aggregate (current Ready pods only). */
    public record PodBreakdown(String pod, Double workingSetPeakMi, Double startupSeconds) {}

    /** All fact groups the checklist needs, plus the JFR ring, the window and per-pod breakdown. */
    public record MeasureResult(String service, int windowMinutes,
                                WorkloadFacts workload, RuntimeFacts runtime,
                                ProfileFacts profile, JfrFacts jfr, Window window,
                                List<PodBreakdown> pods) {}

    /** Caller-supplied sizing policy — all required, no defaults (the skill owns the numbers). */
    public record SizeParams(double peakFactor, double floorSafetyFactor,
                             int roundMi, int warmSeconds, int minSamples,
                             double minRequestRate, double minDeltaMi) {}

    public record Sized(String memory) {}

    public record SizeEvidence(Double workingSetFloorMi, Double workingSetPeakMi,
                               Double heapCommittedMi, Double cpuLimitCores) {}

    /**
     * OK: computed sizing — requests == limits (Guaranteed memory QoS: JVM memory is stable
     * after warm-up and a Burstable JVM is the first OOM-kill candidate on a busy node).
     * BLOCKED: reason set, sizing null (guard not satisfied).
     */
    public record SizeResult(String status, String reason, Sized requests, Sized limits,
                             Integer maxRamPercentage, Integer initialRamPercentage, String gc,
                             SizeEvidence evidence, SizeParams params) {}

    /** Caller-supplied CPU sizing policy — all required (the skill owns the numbers). */
    public record CpuParams(double cpuFactor, int roundMillicores, int warmSeconds, int minSamples,
                            double minRequestRate, double minDeltaMi) {}

    public record CpuEvidence(Double cpuUsageP95Cores, Double cpuRequestCores, Double cpuLimitCores) {}

    /**
     * OK: requests.cpu computed, limits.cpu = current (unchanged). BLOCKED: reason set.
     * clampedToLimit: the computed request exceeded limits.cpu and was capped to it (note explains).
     */
    public record CpuResult(String status, String reason, String requestsCpu, String limitsCpu,
                            boolean clampedToLimit, String note, CpuEvidence evidence, CpuParams params) {}

    /**
     * A blocking diagnosis: thread facts sampled over time WHILE THE OPERATOR'S LOAD RUNS.
     * status OK, or BLOCKED (threads null) when no load is flowing right now.
     */
    public record BlockingResult(String status, String reason, ThreadFacts threads,
                                 int durationSec, Double requestRatePerSec) {}

    public record ProfileTop(List<Frame> frames, Double jitShare, Double gcShare, Double futexWallShare, long samples) {}

    public record StartupResult(String pod, String line, Double seconds, String kind) {}

    // --- measure ---------------------------------------------------------------

    /**
     * {@code minUptimeSeconds}: a freshly rolled pod has no peak, p95 or throttle share yet (the
     * load-guarded checklist items need ~2 min of traffic on THAT pod). When the current pod is
     * younger, wait until it reaches this age, in slices of at most 30 s per call so the caller
     * can narrate progress, before collecting.
     */
    public MeasureResult measure(String service, int windowMinutes, int minUptimeSeconds) {
        int mins = norm(windowMinutes);
        int waited = 0, remaining = 0;
        String note = null;
        var snap = k8s.collect(service, service);
        if (minUptimeSeconds > 0 && snap.uptimeSeconds() != null && snap.uptimeSeconds() < minUptimeSeconds) {
            Double rateNow = prometheus.requestRatePerSec(service, 1);
            if (rateNow == null || rateNow < 1.0) {
                note = "pod is " + snap.uptimeSeconds().intValue() + " s old but no load is flowing ("
                    + (rateNow == null ? "no rate" : String.format("%.2f rps", rateNow))
                    + ") — nothing to wait for; start the service's load and ask again";
            } else {
                int need = minUptimeSeconds - snap.uptimeSeconds().intValue();
                waited = Math.min(MAX_SETTLE_SLICE_SECONDS, need);
                remaining = need - waited;
                logger.info("measure service={} pod={} is {}s old, waiting {}s ({}s more after this call) for minUptime {}s",
                    service, snap.appPodName(), snap.uptimeSeconds().intValue(), waited, remaining, minUptimeSeconds);
                try {
                    Thread.sleep(waited * 1000L);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                snap = k8s.collect(service, service);   // the pod aged; re-read uptime and Ready set
            }
        }
        var f = facts.collect(service, mins, snap);
        var rt = f.runtime();
        var window = new Window(
            rt == null ? null : rt.uptimeSeconds(),
            f.profile() == null ? 0 : f.profile().samples(),
            rt == null ? null : rt.requestRatePerSec(),
            waited, remaining, note);
        return new MeasureResult(service, mins, f.workload(), rt, f.profile(), f.jfr(), window,
            perPodBreakdown(service, mins, snap));
    }

    /** Per-pod peak + startup behind the fleet aggregate, for the Ready pods of the snapshot. */
    private List<PodBreakdown> perPodBreakdown(String service, int windowMinutes, K8sCollector.Snapshot snap) {
        var ready = snap.readyPodNames();
        if (ready == null || ready.isEmpty()) {
            return List.of();
        }
        String container = snap.appContainer() != null ? snap.appContainer() : service;
        var peak = prometheus.perPodPeakMi(service, container, snap.readyPodRegex(), windowMinutes);
        var startup = facts.perPodStartup(service, ready);
        var pods = new LinkedHashSet<>(ready);
        return pods.stream()
            .map(p -> new PodBreakdown(p, peak.get(p), startup.get(p)))
            .toList();
    }

    // --- sizeMemory (arithmetic + guard) ---------------------------------------

    /** Collect facts and size. */
    public SizeResult sizeMemory(String service, int windowMinutes, SizeParams p) {
        return sizeMemory(facts.collect(service, norm(windowMinutes)), p);
    }

    /**
     * Pure sizing over already-collected facts (also the unit-test entry point).
     * Guard: BLOCKED unless {@code uptime > warmSeconds && samples > minSamples}
     * and {@code (requestRate > minRequestRate || peak - floor > minDeltaMi)}.
     * Rule: limits = roundUpMi(max(peak*peakFactor, floor*floorSafetyFactor));
     * requests = limits (Guaranteed); maxRamPercentage = 75; initialRamPercentage = 50;
     * gc = cpuLimit <= 1 ? SerialGC : G1GC.
     */
    public SizeResult sizeMemory(Facts f, SizeParams p) {
        var rt = f.runtime();
        var wl = f.workload();
        Double floor = rt == null ? null : rt.workingSetFloorMi();
        Double peak = rt == null ? null : rt.workingSetPeakMi();
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

    // --- sizeCpu (arithmetic + guard) ------------------------------------------

    public CpuResult sizeCpu(String service, int windowMinutes, CpuParams p) {
        return sizeCpu(facts.collect(service, norm(windowMinutes)), p);
    }

    /**
     * Pure CPU sizing over collected facts. Guard identical to sizeMemory (warm + load).
     * Rule: requests.cpu = roundUp(cpuUsageP95 * cpuFactor, roundMillicores), capped at
     * limits.cpu; limits.cpu unchanged — the boot spike is the startup boost's job, not the
     * steady request's.
     */
    public CpuResult sizeCpu(Facts f, CpuParams p) {
        var rt = f.runtime();
        var wl = f.workload();
        Double p95 = rt == null ? null : rt.cpuUsageP95Cores();
        Double cpuReq = wl == null ? null : wl.cpuRequestCores();
        Double cpuLim = wl == null ? null : wl.cpuLimitCores();
        Double uptime = rt == null ? null : rt.uptimeSeconds();
        Double reqRate = rt == null ? null : rt.requestRatePerSec();
        Double floor = rt == null ? null : rt.workingSetFloorMi();
        Double peak = rt == null ? null : rt.workingSetPeakMi();
        long samples = f.profile() == null ? 0 : f.profile().samples();
        var evidence = new CpuEvidence(p95, cpuReq, cpuLim);

        if (p95 == null) {
            return new CpuResult("BLOCKED", "insufficient measurement: missing CPU usage p95 from Prometheus",
                null, null, false, null, evidence, p);
        }
        boolean warm = uptime != null && uptime > p.warmSeconds() && samples > p.minSamples();
        if (!warm) {
            return new CpuResult("BLOCKED", ("profiling window not warm: uptime=%s (need > %ds), samples=%d (need > %d). "
                + "Run a load phase after (re)start and retry.")
                .formatted(fmt(uptime), p.warmSeconds(), samples, p.minSamples()), null, null, false, null, evidence, p);
        }
        boolean load = (reqRate != null && reqRate > p.minRequestRate())
            || (floor != null && peak != null && peak - floor > p.minDeltaMi());
        if (!load) {
            return new CpuResult("BLOCKED", ("no load observed: requestRate=%s rps (need > %s). Drive traffic and retry.")
                .formatted(fmt(reqRate), fmt(p.minRequestRate())), null, null, false, null, evidence, p);
        }
        long millis = (long) Math.ceil(p95 * p.cpuFactor() * 1000.0);
        long rounded = ((millis + p.roundMillicores() - 1) / p.roundMillicores()) * p.roundMillicores();
        String limits = cpuLim == null ? null : quantity(cpuLim);
        boolean clamped = false;
        String note = null;
        if (cpuLim != null && rounded > Math.round(cpuLim * 1000.0)) {
            clamped = true;
            note = ("computed request %dm exceeds limits.cpu %s; capped to the limit. The container is "
                + "CPU-bound at this load (p95 %.3f cores of %s): raise limits.cpu (and ActiveProcessorCount) "
                + "or reduce CPU per request, then re-measure.").formatted(rounded, limits, p95, limits);
            rounded = Math.round(cpuLim * 1000.0);
        }
        String requests = rounded + "m";
        logger.info("sizeCpu OK p95={} -> requests={} limits={} (unchanged) clamped={}", p95, requests, limits, clamped);
        return new CpuResult("OK", null, requests, limits, clamped, note, evidence, p);
    }

    // --- threadDump / diagnoseBlocking -----------------------------------------

    /**
     * Thread dump across up to {@code sampleN} Ready pods, aggregated (counts summed, frames
     * merged). sampleN <= 1 = newest pod only. null when no dump could be taken or parsed.
     */
    public ThreadFacts threadDump(String service, int sampleN) {
        var refs = k8s.readyPodRefs(service, service);
        if (refs.isEmpty()) {
            var snap = k8s.collect(service, service);   // fallback to the representative pod
            return dump.threads(snap.appPodIP(), snap.appPodName());
        }
        int n = Math.max(1, Math.min(sampleN <= 0 ? 1 : sampleN, refs.size()));
        var dumps = refs.stream().limit(n)
            .map(r -> dump.threads(r.ip(), r.name()))
            .filter(Objects::nonNull)
            .toList();
        if (dumps.isEmpty()) {
            return null;
        }
        if (dumps.size() == 1) {
            return dumps.getFirst();
        }
        return aggregate(dumps, String.join(",", dumps.stream().map(ThreadFacts::pod).toList()), Integer::sum);
    }

    /**
     * Sample the representative pod's thread dump {@code samples} times, {@code intervalMs} apart,
     * and aggregate over TIME. A request-path block on a virtual-thread app is brief — the vthread
     * parks in {@code Future.get()} only for the downstream round-trip — so a single snapshot
     * usually misses it. Counters are the PEAK concurrent value across samples; {@code byState}
     * is the peak per state; {@code topBlockingFrames} counts are summed. Must be taken WHILE
     * load flows. null when no dump could be taken.
     */
    public ThreadFacts threadDumpOverTime(String service, int samples, long intervalMs) {
        int n = Math.max(1, Math.min(samples <= 0 ? 5 : samples, 30));
        long gap = intervalMs <= 0 ? 1000L : Math.min(intervalMs, 5000L);
        var snap = k8s.collect(service, service);
        var dumps = new ArrayList<ThreadFacts>();
        for (int i = 0; i < n; i++) {
            var d = dump.threads(snap.appPodIP(), snap.appPodName());
            if (d != null) {
                dumps.add(d);
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
        if (dumps.isEmpty()) {
            return null;
        }
        return aggregate(dumps, snap.appPodName(), Math::max);
    }

    /**
     * Merge dumps: counters and byState combined with {@code counter} (sum across pods, peak
     * across time), blocking-frame hits always summed, the sample taken from the first dump.
     */
    static ThreadFacts aggregate(List<ThreadFacts> dumps, String pod, IntBinaryOperator counter) {
        var byState = new LinkedHashMap<String, Integer>();
        var frames = new LinkedHashMap<String, Integer>();
        int total = 0, virtual = 0, active = 0, blocked = 0, pool = 0, inTx = 0;
        for (var d : dumps) {
            total = counter.applyAsInt(total, d.total());
            virtual = counter.applyAsInt(virtual, d.virtualThreads());
            active = counter.applyAsInt(active, d.requestThreadsActive());
            blocked = counter.applyAsInt(blocked, d.requestThreadsBlockedInFutureGet());
            pool = counter.applyAsInt(pool, d.requestThreadsWaitingForConnection());
            inTx = counter.applyAsInt(inTx, d.blockedInsideTransaction());
            if (d.byState() != null) {
                d.byState().forEach((k, v) -> byState.merge(k, v, counter::applyAsInt));
            }
            if (d.topBlockingFrames() != null) {
                d.topBlockingFrames().forEach(f -> frames.merge(f.frame(), f.count(), Integer::sum));
            }
        }
        var topFrames = frames.entrySet().stream()
            .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
            .map(e -> new ThreadFacts.FrameCount(e.getKey(), e.getValue()))
            .toList();
        return new ThreadFacts(pod, Instant.now().toString(),
            total, byState, virtual, active, blocked, pool, inTx, topFrames, dumps.getFirst().sample());
    }

    /**
     * Diagnose a request-path block by sampling the JSON thread dump over {@code durationSec}
     * seconds. The sensor drives NO traffic: a blocked request thread (Future.get on a virtual
     * thread) exists only while requests are in flight, and JFR does not record virtual-thread
     * parks, so the caller must have a load run going. Guard: BLOCKED unless the request rate
     * over the last minute exceeds {@code minRequestRate}. Read-only on any image, including CRaC.
     * Defaults 20 s at 500 ms = 40 dumps: a ~10 ms block at 50 rps is present in a given dump
     * with p ≈ 0.4, so 12 dumps missed it once in ~25 runs; 40 dumps make a miss negligible.
     * Each dump is a safepoint in the app JVM; 40 in 20 s is the accepted cost of the diagnosis.
     */
    public BlockingResult diagnoseBlocking(String service, int durationSec, long intervalMs,
                                           double minRequestRate) {
        int dur = Math.max(3, Math.min(durationSec <= 0 ? 20 : durationSec, 60));
        long gap = intervalMs <= 0 ? 500L : Math.min(intervalMs, 5000L);
        int samples = Math.max(2, (int) ((dur * 1000L) / gap));
        Double rateNow = prometheus.requestRatePerSec(service, 1);
        if (rateNow == null || rateNow <= minRequestRate) {
            return new BlockingResult("BLOCKED",
                ("no load flowing now: requestRate(1m)=%s rps (need > %s). Start the load run, then retry "
                    + "while it is running.").formatted(fmt(rateNow), fmt(minRequestRate)),
                null, dur, rateNow);
        }
        var threads = threadDumpOverTime(service, samples, gap);
        if (threads == null) {
            return new BlockingResult("BLOCKED",
                "no thread dump could be taken: is the profiler sidecar attached (perf-profile/sidecar label) and its /dump reachable?",
                null, dur, rateNow);
        }
        return new BlockingResult("OK", null, threads, dur, rateNow);
    }

    // --- profileTop / startupLog -----------------------------------------------

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

    /** Cores as a K8s quantity: whole cores as "1", fractions as millicores "500m". */
    static String quantity(double cores) {
        if (cores == Math.rint(cores)) {
            return String.valueOf((long) cores);
        }
        return Math.round(cores * 1000.0) + "m";
    }

    /** Round a MiB value UP to the next multiple of stepMi, formatted as a K8s quantity. */
    static String roundUpMi(double mi, int stepMi) {
        long v = (long) Math.ceil(mi);
        long rounded = ((v + stepMi - 1) / stepMi) * stepMi;
        return rounded + "Mi";
    }

    private static int norm(int windowMinutes) {
        return windowMinutes <= 0 ? DEFAULT_WINDOW_MINUTES : windowMinutes;
    }

    private static String fmt(Double v) {
        return v == null ? "n/a" : "%.2f".formatted(v);
    }
}
