package com.example.perf.sensor;

import com.example.perf.sensor.SensorService.MeasureResult;
import com.example.perf.sensor.SensorService.ProfileTop;
import com.example.perf.sensor.SensorService.SizeParams;
import com.example.perf.sensor.SensorService.SizeResult;
import com.example.perf.sensor.SensorService.StartupResult;
import com.example.perf.sensor.facts.ThreadFacts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.stereotype.Component;

/**
 * The deterministic sensor tools exposed over MCP. Every tool returns a JSON
 * record; no LLM runs in this process. Units: memory MiB, CPU cores, time seconds,
 * shares percent. {@code service} is the Pyroscope service_name = Kubernetes
 * Deployment name (e.g. the workload you are optimizing).
 */
@Component
public class SensorMcpTools {

    private static final Logger logger = LoggerFactory.getLogger(SensorMcpTools.class);

    private final SensorService sensor;

    public SensorMcpTools(SensorService sensor) {
        this.sensor = sensor;
    }

    @Tool(description = """
        Measure a Java service on EKS: Kubernetes desired-state (requests/limits in MiB/cores,
        cpu resizePolicy, JAVA_TOOL_OPTIONS, image tag, replicas, readiness probe, sidecars) plus
        measured runtime (working-set floor/peak MiB, heap committed MiB, GC name, effective CPUs,
        startup seconds, restarts), a CPU/wall profile summary (jit/gc/futex shares, samples), and
        the window {uptimeSeconds, samples, requestRatePerSec}. Facts only — everything the
        checklist needs to score items 1-9. Deterministic; no LLM.""")
    public MeasureResult measure(
        @ToolParam(description = "Pyroscope service_name = Deployment name") String service,
        @ToolParam(description = "Look-back window in minutes (default 15)", required = false) Integer windowMinutes) {
        logger.info("MCP measure service={} window={}", service, windowMinutes);
        return sensor.measure(service, orDefault(windowMinutes));
    }

    @Tool(description = """
        Compute memory requests/limits (MiB), MaxRAMPercentage and GC for a Java service from its
        MEASURED working-set, with a guard that must not be skipped. Returns status OK or BLOCKED.
        BLOCKED (with a reason, no sizing) unless the profiling window is warm (uptime > warmSeconds
        AND samples > minSamples) and load was observed (requestRate > minRequestRate OR
        rssPeak-rssFloor > minDeltaMi). All policy parameters are REQUIRED and supplied by the
        caller (the optimization skill owns the numbers; this tool owns only the arithmetic):
        requests = roundUpMi(floor*floorFactor); limits = roundUpMi(max(peak*peakFactor,
        floor*floorSafetyFactor)); MaxRAMPercentage = 75; GC = cpuLimit <= 1 ? SerialGC : G1GC.""")
    public SizeResult sizeMemory(
        @ToolParam(description = "Pyroscope service_name = Deployment name") String service,
        @ToolParam(description = "Look-back window in minutes") int windowMinutes,
        @ToolParam(description = "requests = floor * this (e.g. 1.25)") double floorFactor,
        @ToolParam(description = "limit >= peak * this (e.g. 1.40)") double peakFactor,
        @ToolParam(description = "limit >= floor * this (e.g. 1.90), protects an under-observed peak") double floorSafetyFactor,
        @ToolParam(description = "round memory up to a multiple of this many MiB (e.g. 64)") int roundMi,
        @ToolParam(description = "guard: minimum uptime seconds before sizing (e.g. 120)") int warmSeconds,
        @ToolParam(description = "guard: minimum profile weight — Pyroscope numTicks, i.e. 'a real profile exists' (e.g. 100)") int minSamples,
        @ToolParam(description = "guard: minimum request rate rps that counts as load (e.g. 1)") double minRequestRate,
        @ToolParam(description = "guard: minimum peak-floor MiB delta that counts as load (e.g. 64)") double minDeltaMi) {
        logger.info("MCP sizeMemory service={} window={}", service, windowMinutes);
        return sensor.sizeMemory(service, windowMinutes,
            new SizeParams(floorFactor, peakFactor, floorSafetyFactor, roundMi, warmSeconds,
                minSamples, minRequestRate, minDeltaMi));
    }

    @Tool(description = """
        Summarized thread dump for a Java service via the profiler sidecar /dump (JSON jcmd thread
        dump, never raw): total threads, count by state, virtual thread count,
        requestThreadsBlockedInFutureGet (request-path threads parked in a blocking Future.get/join),
        carriersParkedInPoolWait, topBlockingFrames [{frame, count}] and a small thread sample.
        Includes pod(s) and timestamp. sampleN>1 samples that many Ready pods and aggregates
        (use it at higher replica counts so a blocking call on one pod is not missed). Use to
        confirm a blocking call on the request path.""")
    public ThreadFacts threadDump(
        @ToolParam(description = "Pyroscope service_name = Deployment name") String service,
        @ToolParam(description = "number of Ready pods to sample and aggregate (default 1 = newest pod)", required = false) Integer sampleN) {
        logger.info("MCP threadDump service={} sampleN={}", service, sampleN);
        return sensor.threadDump(service, sampleN == null ? 1 : sampleN);
    }

    @Tool(description = """
        Top hottest leaf frames for a Java service from Pyroscope, with self% shares. type=cpu gives
        jitShare and gcShare (% of CPU samples); type=wall gives futexWallShare (% of wall samples
        parked in futex/lock waits). Use cpu to see JIT/class-loading dominance (startup), wall to
        see off-CPU blocking (latency). Returns frames, the relevant share, and the profile
        weight (Pyroscope numTicks; profiled-time units, not a literal sample count).""")
    public ProfileTop profileTop(
        @ToolParam(description = "Pyroscope service_name = Deployment name") String service,
        @ToolParam(description = "profile type: cpu or wall") String type,
        @ToolParam(description = "Look-back window in minutes (default 15)", required = false) Integer windowMinutes,
        @ToolParam(description = "max frames to return (default 15)", required = false) Integer limit) {
        logger.info("MCP profileTop service={} type={}", service, type);
        return sensor.profileTop(service, type, orDefault(windowMinutes), limit == null ? 15 : limit);
    }

    @Tool(description = """
        The last startup line from the app container log: {pod, line, seconds, kind} where kind is
        Started (cold start) or Restored (CRaC checkpoint restore). Complements the measured startup
        seconds and verifies a CRaC restore. Generic regex; returns nulls if no line is present.""")
    public StartupResult startupLog(
        @ToolParam(description = "Pyroscope service_name = Deployment name") String service) {
        logger.info("MCP startupLog service={}", service);
        return sensor.startupLog(service);
    }

    private static int orDefault(Integer windowMinutes) {
        return windowMinutes == null || windowMinutes <= 0 ? 15 : windowMinutes;
    }
}
