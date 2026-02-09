package com.example.ai.jvmanalyzer;

import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordingFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Path;
import java.util.*;

/**
 * Parses JFR files using the built-in jdk.jfr.consumer API.
 * Extracts runtime metrics: CPU load, GC heap, JVM info, and sample count.
 * Stack hotspot analysis is delegated to async-profiler's jfr-converter
 * which produces collapsed stacks with correct frame attribution.
 */
public class JfrParser {

    private static final Logger logger = LoggerFactory.getLogger(JfrParser.class);

    public record JfrSummary(
        List<CpuLoad> cpuLoads,
        List<GcHeap> gcHeaps,
        String jvmInfo,
        int totalSamples
    ) {}

    public record CpuLoad(double jvmUser, double jvmSystem, double machineTotal) {}
    public record GcHeap(long heapUsed, long committed) {}

    public static JfrSummary parse(Path jfrFile) throws IOException {
        var cpuLoads = new ArrayList<CpuLoad>();
        var gcHeaps = new ArrayList<GcHeap>();
        String jvmInfo = "";
        int totalSamples = 0;

        try (var recording = new RecordingFile(jfrFile)) {
            while (recording.hasMoreEvents()) {
                RecordedEvent event = recording.readEvent();
                String eventName = event.getEventType().getName();

                switch (eventName) {
                    case "profiler.WallClockSample", "jdk.ExecutionSample" -> totalSamples++;
                    case "jdk.CPULoad" -> cpuLoads.add(new CpuLoad(
                        getDouble(event, "jvmUser"),
                        getDouble(event, "jvmSystem"),
                        getDouble(event, "machineTotal")
                    ));
                    case "jdk.GCHeapSummary" -> {
                        long committed = 0;
                        try { committed = event.getValue("heapSpace.committedSize"); }
                        catch (Exception _) {}
                        gcHeaps.add(new GcHeap(getLong(event, "heapUsed"), committed));
                    }
                    case "jdk.JVMInformation" -> jvmInfo = getString(event, "jvmVersion")
                        + " | args: " + getString(event, "jvmArguments");
                }
            }
        } catch (Exception e) {
            logger.warn("JFR parsing incomplete (file may be truncated): {}", e.getMessage());
        }

        logger.info("Parsed JFR: {} samples, {} CPU events, {} GC events",
            totalSamples, cpuLoads.size(), gcHeaps.size());

        return new JfrSummary(cpuLoads, gcHeaps, jvmInfo, totalSamples);
    }

    private static double getDouble(RecordedEvent event, String field) {
        try { return event.getDouble(field); }
        catch (Exception _) { return 0.0; }
    }

    private static long getLong(RecordedEvent event, String field) {
        try { return event.getLong(field); }
        catch (Exception _) { return 0L; }
    }

    private static String getString(RecordedEvent event, String field) {
        try { return event.getString(field); }
        catch (Exception _) { return ""; }
    }

    /**
     * Formats JFR runtime metrics as text for model input.
     * Stack hotspots are provided separately via collapsed stacks from jfr-converter.
     */
    public static String formatForModel(JfrSummary summary) {
        var sb = new StringBuilder();

        sb.append("## JFR Runtime Metrics\n\n");

        if (!summary.jvmInfo().isEmpty()) {
            sb.append("**JVM:** ").append(summary.jvmInfo()).append("\n\n");
        }

        sb.append("**Total samples:** ").append(summary.totalSamples()).append("\n\n");

        if (!summary.cpuLoads().isEmpty()) {
            var stats = summary.cpuLoads();
            double avgUser = stats.stream().mapToDouble(CpuLoad::jvmUser).average().orElse(0);
            double maxUser = stats.stream().mapToDouble(CpuLoad::jvmUser).max().orElse(0);
            double avgMachine = stats.stream().mapToDouble(CpuLoad::machineTotal).average().orElse(0);
            sb.append("**CPU load (%d samples):**\n".formatted(stats.size()));
            sb.append("  JVM user:      avg=%.1f%% max=%.1f%%\n".formatted(avgUser * 100, maxUser * 100));
            sb.append("  Machine total: avg=%.1f%%\n\n".formatted(avgMachine * 100));
        }

        if (!summary.gcHeaps().isEmpty()) {
            var last = summary.gcHeaps().getLast();
            var maxUsed = summary.gcHeaps().stream().mapToLong(GcHeap::heapUsed).max().orElse(0);
            var minUsed = summary.gcHeaps().stream().mapToLong(GcHeap::heapUsed).min().orElse(0);
            sb.append("**GC heap (%d events):**\n".formatted(summary.gcHeaps().size()));
            sb.append("  used: %d-%dMB, committed: %dMB\n\n".formatted(
                minUsed / (1024 * 1024), maxUsed / (1024 * 1024),
                last.committed() / (1024 * 1024)
            ));
        }

        return sb.toString();
    }
}
