package com.example.perf.analyzer;

import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordingFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Deterministic JFR event extractor.
 *
 * Reads an always-on default.jfc recording (dumped by perf-collector via
 * `jcmd JFR.dump`) and produces top-5 aggregates per event type. The
 * aggregates are small and structured, so the LLM prompt stays compact
 * and we don't waste tokens on raw event streams.
 *
 * Events extracted:
 *   jdk.ExecutionSample        -> count
 *   jdk.CPULoad                -> avg/max JVM user/system + machine total
 *   jdk.GCHeapSummary          -> min/max used + last committed
 *   jdk.JVMInformation         -> version + args as a single string
 *   jdk.GCPhasePause           -> top-5 by total duration, grouped by cause+name
 *   jdk.Compilation            -> top-5 compiled methods by count
 *   jdk.Deoptimization         -> top-5 reasons
 *   jdk.JavaMonitorEnter       -> top-5 monitors by total wait
 *   jdk.SafepointBegin         -> top-5 operations by total pause
 *   jdk.ContainerConfiguration -> container type, cpu quota/period, mem limit
 *
 * All per-event records are inner records of this class so the package
 * stays flat.
 */
@Component
public class JfrParser {

    private static final Logger logger = LoggerFactory.getLogger(JfrParser.class);
    private static final int TOP_N = 5;

    public JfrSummary parse(Path jfrFile) throws IOException {
        int totalSamples = 0;
        String jvmInfo = "";
        ContainerConfig container = ContainerConfig.empty();

        var cpuAcc = new CpuAcc();
        var heapAcc = new HeapAcc();
        var gcPauses = new HashMap<String, DurationBucket>();
        var compMethods = new HashMap<String, CountDuration>();
        var deopts = new HashMap<String, CountOnly>();
        var monitors = new HashMap<String, DurationBucket>();
        var safepoints = new HashMap<String, DurationBucket>();

        try (var recording = new RecordingFile(jfrFile)) {
            while (recording.hasMoreEvents()) {
                RecordedEvent event;
                try { event = recording.readEvent(); }
                catch (Exception e) {
                    logger.warn("JFR parse error (continuing): {}", e.getMessage());
                    continue;
                }
                var name = event.getEventType().getName();
                switch (name) {
                    case "profiler.WallClockSample", "jdk.ExecutionSample" -> totalSamples++;
                    case "jdk.CPULoad" -> cpuAcc.add(
                        getDouble(event, "jvmUser"),
                        getDouble(event, "jvmSystem"),
                        getDouble(event, "machineTotal"));
                    case "jdk.GCHeapSummary" -> heapAcc.add(
                        getLong(event, "heapUsed"),
                        getLongOrFallback(event, "heapSpace.committedSize", "committedSize"));
                    case "jdk.JVMInformation" -> {
                        if (jvmInfo.isEmpty()) {
                            jvmInfo = getString(event, "jvmVersion")
                                + " | args: " + getString(event, "jvmArguments");
                        }
                    }
                    case "jdk.GCPhasePause", "jdk.GCPhasePauseLevel1", "jdk.GCPhaseParallel" -> {
                        var cause = getString(event, "cause");
                        var phase = getString(event, "name");
                        var key = (cause == null || cause.isBlank() ? "unknown" : cause)
                            + " / " + (phase == null || phase.isBlank() ? name : phase);
                        gcPauses.computeIfAbsent(key, _ -> new DurationBucket())
                            .add(event.getDuration().toMillis());
                    }
                    case "jdk.Compilation" -> {
                        var method = getString(event, "method");
                        compMethods.computeIfAbsent(method, _ -> new CountDuration())
                            .add(event.getDuration().toMillis());
                    }
                    case "jdk.Deoptimization" -> {
                        var reason = getString(event, "reason");
                        var action = getString(event, "action");
                        var key = (reason == null ? "unknown" : reason) + " / " + (action == null ? "" : action);
                        deopts.computeIfAbsent(key, _ -> new CountOnly()).add();
                    }
                    case "jdk.JavaMonitorEnter" -> {
                        var monitorClass = getString(event, "monitorClass");
                        monitors.computeIfAbsent(monitorClass == null ? "unknown" : monitorClass,
                                _ -> new DurationBucket())
                            .add(event.getDuration().toMillis());
                    }
                    case "jdk.SafepointBegin" -> {
                        var op = getString(event, "safepointId");
                        var operation = firstNonBlank(getString(event, "operation"), op, "Safepoint");
                        safepoints.computeIfAbsent(operation, _ -> new DurationBucket())
                            .add(event.getDuration().toMillis());
                    }
                    case "jdk.ContainerConfiguration" -> container = new ContainerConfig(
                        getString(event, "containerType"),
                        getLong(event, "cpuQuota"),
                        getLong(event, "cpuSlicePeriod"),
                        getLong(event, "memoryLimit"),
                        getLong(event, "effectiveCpuCount"));
                    default -> { /* ignore other events */ }
                }
            }
        }

        logger.info(
            "Parsed JFR: samples={} gcPauseBuckets={} compiledMethods={} deopts={} monitors={} safepoints={}",
            totalSamples, gcPauses.size(), compMethods.size(), deopts.size(),
            monitors.size(), safepoints.size());

        return new JfrSummary(
            totalSamples,
            cpuAcc.toStats(),
            heapAcc.toStats(),
            topGcPauses(gcPauses),
            topCompiledMethods(compMethods),
            topDeopts(deopts),
            topMonitors(monitors),
            topSafepoints(safepoints),
            jvmInfo,
            container);
    }

    /** Produces Markdown for AiService.AnalysisContext. */
    public String formatForModel(JfrSummary s) {
        var sb = new StringBuilder();
        sb.append("### JFR runtime metrics\n\n");
        if (!s.jvmInfo().isEmpty()) sb.append("- **JVM:** ").append(s.jvmInfo()).append("\n");
        sb.append("- **Total samples:** ").append(s.totalSamples()).append("\n\n");

        var cpu = s.cpuLoad();
        if (cpu.sampleCount() > 0) {
            sb.append("**CPU load** (").append(cpu.sampleCount()).append(" samples): ");
            sb.append("user avg=%.1f%% max=%.1f%%, system avg=%.1f%%, machine avg=%.1f%%\n\n"
                .formatted(cpu.jvmUserAvg() * 100, cpu.jvmUserMax() * 100,
                    cpu.jvmSystemAvg() * 100, cpu.machineTotalAvg() * 100));
        }

        var heap = s.heap();
        if (heap.sampleCount() > 0) {
            sb.append("**GC heap** (")
                .append(heap.sampleCount()).append(" samples): used ")
                .append(mb(heap.heapUsedMin())).append("MB .. ")
                .append(mb(heap.heapUsedMax())).append("MB, committed ")
                .append(mb(heap.heapCommittedLast())).append("MB\n\n");
        }

        var c = s.container();
        if (c != null && !"unknown".equals(c.containerType())) {
            sb.append("**Container**: ").append(c.containerType())
                .append(", cpuQuota=").append(c.cpuQuota())
                .append(", cpuPeriod=").append(c.cpuPeriod())
                .append(", effectiveCpuCount=").append(c.effectiveCpuCount())
                .append(", memoryLimit=").append(mb(c.memoryLimit())).append("MB\n\n");
        }

        if (!s.topGcPauses().isEmpty()) {
            sb.append("**Top GC pauses** (by total duration):\n");
            for (var p : s.topGcPauses()) {
                sb.append("- `").append(p.cause()).append(" / ").append(p.name())
                    .append("` — count=").append(p.count())
                    .append(", total=").append(String.format("%.1f", p.totalMs())).append("ms")
                    .append(", p95=").append(String.format("%.1f", p.p95Ms())).append("ms\n");
            }
            sb.append('\n');
        }
        if (!s.topCompiledMethods().isEmpty()) {
            sb.append("**Top JIT compilations** (by count):\n");
            for (var cm : s.topCompiledMethods()) {
                sb.append("- `").append(cm.method())
                    .append("` — count=").append(cm.count())
                    .append(", total=").append(String.format("%.1f", cm.totalMs())).append("ms\n");
            }
            sb.append('\n');
        }
        if (!s.topDeopts().isEmpty()) {
            sb.append("**Top deoptimizations**:\n");
            for (var d : s.topDeopts()) {
                sb.append("- ").append(d.reason()).append(" / ").append(d.action())
                    .append(" — count=").append(d.count()).append('\n');
            }
            sb.append('\n');
        }
        if (!s.topMonitors().isEmpty()) {
            sb.append("**Top monitor contention** (jdk.JavaMonitorEnter):\n");
            for (var m : s.topMonitors()) {
                sb.append("- `").append(m.monitorClass())
                    .append("` — count=").append(m.count())
                    .append(", total=").append(String.format("%.1f", m.totalMs())).append("ms")
                    .append(", p95=").append(String.format("%.1f", m.p95Ms())).append("ms\n");
            }
            sb.append('\n');
        }
        if (!s.topSafepoints().isEmpty()) {
            sb.append("**Top safepoint operations** (by total pause):\n");
            for (var sp : s.topSafepoints()) {
                sb.append("- `").append(sp.operation())
                    .append("` — count=").append(sp.count())
                    .append(", total=").append(String.format("%.1f", sp.totalMs())).append("ms\n");
            }
            sb.append('\n');
        }
        return sb.toString();
    }

    // --- helpers ---

    private static List<GcPause> topGcPauses(Map<String, DurationBucket> map) {
        return map.entrySet().stream()
            .sorted(Comparator.<Map.Entry<String, DurationBucket>>comparingDouble(
                e -> e.getValue().totalMs).reversed())
            .limit(TOP_N)
            .map(e -> {
                var parts = e.getKey().split(" / ", 2);
                return new GcPause(parts[0], parts.length > 1 ? parts[1] : "",
                    e.getValue().count, e.getValue().totalMs, e.getValue().p95());
            })
            .toList();
    }

    private static List<CompilationCount> topCompiledMethods(Map<String, CountDuration> map) {
        return map.entrySet().stream()
            .sorted(Comparator.<Map.Entry<String, CountDuration>>comparingLong(
                e -> e.getValue().count).reversed())
            .limit(TOP_N)
            .map(e -> new CompilationCount(e.getKey(), e.getValue().count, e.getValue().totalMs))
            .toList();
    }

    private static List<DeoptReason> topDeopts(Map<String, CountOnly> map) {
        return map.entrySet().stream()
            .sorted(Comparator.<Map.Entry<String, CountOnly>>comparingLong(
                e -> e.getValue().count).reversed())
            .limit(TOP_N)
            .map(e -> {
                var parts = e.getKey().split(" / ", 2);
                return new DeoptReason(parts[0], parts.length > 1 ? parts[1] : "", e.getValue().count);
            })
            .toList();
    }

    private static List<MonitorContention> topMonitors(Map<String, DurationBucket> map) {
        return map.entrySet().stream()
            .sorted(Comparator.<Map.Entry<String, DurationBucket>>comparingDouble(
                e -> e.getValue().totalMs).reversed())
            .limit(TOP_N)
            .map(e -> new MonitorContention(e.getKey(), e.getValue().count,
                e.getValue().totalMs, e.getValue().p95()))
            .toList();
    }

    private static List<SafepointReason> topSafepoints(Map<String, DurationBucket> map) {
        return map.entrySet().stream()
            .sorted(Comparator.<Map.Entry<String, DurationBucket>>comparingDouble(
                e -> e.getValue().totalMs).reversed())
            .limit(TOP_N)
            .map(e -> new SafepointReason(e.getKey(), e.getValue().count, e.getValue().totalMs))
            .toList();
    }

    private static double getDouble(RecordedEvent event, String field) {
        try { return event.getDouble(field); } catch (Exception _) { return 0.0; }
    }
    private static long getLong(RecordedEvent event, String field) {
        try { return event.getLong(field); } catch (Exception _) { return 0L; }
    }
    private static long getLongOrFallback(RecordedEvent event, String primary, String fallback) {
        try { return event.getLong(primary); } catch (Exception _) {}
        try { return event.getLong(fallback); } catch (Exception _) { return 0L; }
    }
    private static String getString(RecordedEvent event, String field) {
        try { var v = event.getValue(field); return v == null ? "" : String.valueOf(v); }
        catch (Exception _) { return ""; }
    }
    private static String firstNonBlank(String... s) {
        for (var v : s) if (v != null && !v.isBlank()) return v;
        return "";
    }
    private static long mb(long bytes) { return bytes / (1024 * 1024); }

    // === Aggregated result + per-event records, inlined for flat package layout ===

    public record JfrSummary(
        int totalSamples,
        CpuLoadStats cpuLoad,
        GcHeapStats heap,
        List<GcPause> topGcPauses,
        List<CompilationCount> topCompiledMethods,
        List<DeoptReason> topDeopts,
        List<MonitorContention> topMonitors,
        List<SafepointReason> topSafepoints,
        String jvmInfo,
        ContainerConfig container
    ) {}

    public record CpuLoadStats(
        double jvmUserAvg, double jvmUserMax,
        double jvmSystemAvg, double jvmSystemMax,
        double machineTotalAvg,
        int sampleCount
    ) {
        public static CpuLoadStats empty() { return new CpuLoadStats(0, 0, 0, 0, 0, 0); }
    }

    public record GcHeapStats(long heapUsedMin, long heapUsedMax, long heapCommittedLast, int sampleCount) {
        public static GcHeapStats empty() { return new GcHeapStats(0, 0, 0, 0); }
    }

    public record GcPause(String cause, String name, long count, double totalMs, double p95Ms) {}
    public record CompilationCount(String method, long count, double totalMs) {}
    public record DeoptReason(String reason, String action, long count) {}
    public record MonitorContention(String monitorClass, long count, double totalMs, double p95Ms) {}
    public record SafepointReason(String operation, long count, double totalMs) {}

    public record ContainerConfig(
        String containerType, long cpuQuota, long cpuPeriod, long memoryLimit, long effectiveCpuCount
    ) {
        public static ContainerConfig empty() { return new ContainerConfig("unknown", 0, 0, 0, 0); }
    }

    // === Parse-time accumulators (not thread safe; single-threaded parse) ===

    private static final class CpuAcc {
        private double userSum, userMax, sysSum, sysMax, machineSum;
        private int count;
        void add(double user, double sys, double machine) {
            userSum += user; userMax = Math.max(userMax, user);
            sysSum  += sys;  sysMax  = Math.max(sysMax, sys);
            machineSum += machine;
            count++;
        }
        CpuLoadStats toStats() {
            if (count == 0) return CpuLoadStats.empty();
            return new CpuLoadStats(userSum / count, userMax, sysSum / count, sysMax,
                machineSum / count, count);
        }
    }
    private static final class HeapAcc {
        private long min = Long.MAX_VALUE, max = Long.MIN_VALUE, lastCommitted;
        private int count;
        void add(long used, long committed) {
            if (used > 0) { min = Math.min(min, used); max = Math.max(max, used); }
            if (committed > 0) lastCommitted = committed;
            count++;
        }
        GcHeapStats toStats() {
            if (count == 0) return GcHeapStats.empty();
            return new GcHeapStats(min == Long.MAX_VALUE ? 0 : min,
                max == Long.MIN_VALUE ? 0 : max, lastCommitted, count);
        }
    }
    private static final class DurationBucket {
        long count;
        double totalMs;
        final List<Double> samples = new ArrayList<>();
        void add(double durationMs) {
            count++; totalMs += durationMs;
            if (samples.size() < 4096) samples.add(durationMs);
        }
        double p95() {
            if (samples.isEmpty()) return 0;
            var sorted = new ArrayList<>(samples);
            sorted.sort(Double::compare);
            var idx = (int) Math.floor(0.95 * (sorted.size() - 1));
            return sorted.get(idx);
        }
    }
    private static final class CountDuration {
        long count;
        double totalMs;
        void add(double durationMs) { count++; totalMs += durationMs; }
    }
    private static final class CountOnly {
        long count;
        void add() { count++; }
    }
}
