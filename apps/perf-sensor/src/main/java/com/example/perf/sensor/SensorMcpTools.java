package com.example.perf.sensor;

import com.example.perf.sensor.SensorService.BlockingResult;
import com.example.perf.sensor.SensorService.CpuParams;
import com.example.perf.sensor.SensorService.CpuResult;
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
 * The deterministic sensor tools exposed over MCP. Every tool returns a JSON record; no LLM
 * runs in this process. Units: memory MiB, CPU cores, time seconds, shares percent.
 * {@code service} is the Pyroscope service_name = Kubernetes Deployment name = namespace =
 * app container name (the sensor's naming contract, see README).
 */
@Component
public class SensorMcpTools {

    private static final Logger logger = LoggerFactory.getLogger(SensorMcpTools.class);
    private static final String SERVICE_PARAM = "Pyroscope service_name = Deployment name = namespace";

    private final SensorService sensor;

    public SensorMcpTools(SensorService sensor) {
        this.sensor = sensor;
    }

    @Tool(description = """
        Measure a Java service on EKS: Kubernetes desired-state (requests/limits in MiB/cores,
        cpu resizePolicy, JAVA_TOOL_OPTIONS, image tag, replicas, probes with paths/budgets/initial
        delays, terminationGracePeriodSeconds, preStop sleep, sidecars) plus measured runtime
        (working-set floor/peak MiB, heap committed MiB, observed MaxHeapSize/InitialHeapSize MiB,
        GC name, effective CPUs, CPU usage p95 cores, CFS throttled share (throttled s / used s, last 5 min, boot excluded), startup
        seconds, restarts, last termination reason, HTTP latency mean/max ms), a CPU/wall profile
        summary (jit/gc/futex shares of the whole profile, samples), the JVM's own JFR ring facts (jfr: container
        limits as the JVM read them incl. effectiveCpuCount, jvmArgs, GC pauses count/max/total,
        VirtualThreadPinned, top monitors, safepoint total, JIT compilation count/time), and the
        window {uptimeSeconds, samples, requestRatePerSec}. Facts only — everything the checklist
        needs except the thread dump under load. Deterministic; no LLM. minUptimeSeconds: if the
        current pod is younger than this, the sensor waits up to 30 s per call and reports
        window.settleRemainingSeconds; while > 0, tell the user how long is left and call again
        (facts are settled when it is 0). window.settleNote explains when it did not wait (no
        load flowing). Use 120 for a checklist score so a freshly rolled pod has data.""")
    public MeasureResult measure(
        @ToolParam(description = SERVICE_PARAM) String service,
        @ToolParam(description = "Look-back window in minutes (default 15)", required = false) Integer windowMinutes,
        @ToolParam(description = "wait until the current pod is at least this old, seconds (default 0 = no wait; waits at most 30 s per call, see window.settleRemainingSeconds)", required = false) Integer minUptimeSeconds) {
        logger.info("MCP measure service={} window={} minUptime={}", service, windowMinutes, minUptimeSeconds);
        return sensor.measure(service, orDefault(windowMinutes), minUptimeSeconds == null ? 0 : minUptimeSeconds);
    }

    @Tool(description = """
        Compute memory requests/limits (MiB), MaxRAMPercentage, InitialRAMPercentage and GC for a
        Java service from its MEASURED working set, with a guard that must not be skipped. Returns
        status OK or BLOCKED. BLOCKED (with a reason, no sizing) unless the profiling window is warm
        (uptime > warmSeconds AND samples > minSamples) and load was observed (requestRate >
        minRequestRate OR workingSetPeak-workingSetFloor > minDeltaMi). All policy parameters are
        REQUIRED and supplied by the caller (the optimization skill owns the numbers; this tool owns
        only the arithmetic): limits = roundUpMi(max(peak*peakFactor, floor*floorSafetyFactor));
        requests = limits (Guaranteed memory QoS); MaxRAMPercentage = 75; InitialRAMPercentage = 50;
        GC = cpuLimit <= 1 ? SerialGC : G1GC.""")
    public SizeResult sizeMemory(
        @ToolParam(description = SERVICE_PARAM) String service,
        @ToolParam(description = "Look-back window in minutes") int windowMinutes,
        @ToolParam(description = "limit >= peak * this (e.g. 1.40)") double peakFactor,
        @ToolParam(description = "limit >= floor * this (e.g. 1.50), protects an under-observed peak") double floorSafetyFactor,
        @ToolParam(description = "round memory up to a multiple of this many MiB (e.g. 128)") int roundMi,
        @ToolParam(description = "guard: minimum uptime seconds before sizing (e.g. 120)") int warmSeconds,
        @ToolParam(description = "guard: minimum CPU profile samples in the window, i.e. 'a real profile exists' (e.g. 100)") int minSamples,
        @ToolParam(description = "guard: minimum request rate rps that counts as load (e.g. 1)") double minRequestRate,
        @ToolParam(description = "guard: minimum peak-floor MiB delta that counts as load (e.g. 64)") double minDeltaMi) {
        logger.info("MCP sizeMemory service={} window={}", service, windowMinutes);
        return sensor.sizeMemory(service, windowMinutes,
            new SizeParams(peakFactor, floorSafetyFactor, roundMi, warmSeconds,
                minSamples, minRequestRate, minDeltaMi));
    }

    @Tool(description = """
        Compute the steady-state CPU request for a Java service from its MEASURED CPU usage, with
        the same warm/load guard as sizeMemory. Returns status OK or BLOCKED. requests.cpu =
        roundUp(cpuUsageP95Cores * cpuFactor, roundMillicores) as millicores, capped at limits.cpu
        (clampedToLimit=true with a note when capped: the container is CPU-bound at this load);
        limits.cpu is returned UNCHANGED (the boot spike is handled by a startup CPU boost /
        in-place resize, not by a permanently high request). All policy parameters are REQUIRED
        and supplied by the caller (the optimization skill owns the numbers).""")
    public CpuResult sizeCpu(
        @ToolParam(description = SERVICE_PARAM) String service,
        @ToolParam(description = "Look-back window in minutes") int windowMinutes,
        @ToolParam(description = "requests.cpu = p95 usage * this (e.g. 1.5)") double cpuFactor,
        @ToolParam(description = "round requests.cpu up to a multiple of this many millicores (e.g. 50)") int roundMillicores,
        @ToolParam(description = "guard: minimum uptime seconds before sizing (e.g. 120)") int warmSeconds,
        @ToolParam(description = "guard: minimum CPU profile samples in the window (e.g. 100)") int minSamples,
        @ToolParam(description = "guard: minimum request rate rps that counts as load (e.g. 1)") double minRequestRate,
        @ToolParam(description = "guard: minimum peak-floor MiB delta that counts as load (e.g. 64)") double minDeltaMi) {
        logger.info("MCP sizeCpu service={} window={}", service, windowMinutes);
        return sensor.sizeCpu(service, windowMinutes,
            new CpuParams(cpuFactor, roundMillicores, warmSeconds, minSamples, minRequestRate, minDeltaMi));
    }

    @Tool(description = """
        Summarized thread dump for a Java service via the profiler sidecar /dump (JSON jcmd thread
        dump, never raw): total threads, count by state, virtual thread count,
        requestThreadsActive (in-flight request threads = observed concurrency),
        requestThreadsBlockedInFutureGet (request-path threads parked in a blocking Future.get/join),
        requestThreadsWaitingForConnection (request threads parked in the connection pool's borrow),
        blockedInsideTransaction (blocked while a transaction interceptor is on the stack: remote
        I/O inside a DB transaction, holding a pooled connection), topBlockingFrames [{frame, count}]
        and a small thread sample. Includes pod(s) and timestamp. sampleN>1 samples that many Ready
        pods and aggregates (use it at higher replica counts so a blocking call on one pod is not
        missed). Returns null when no dump could be taken or parsed — treat as UNKNOWN, not as
        "nothing is blocked". Use to confirm a blocking call on the request path.""")
    public ThreadFacts threadDump(
        @ToolParam(description = SERVICE_PARAM) String service,
        @ToolParam(description = "number of Ready pods to sample and aggregate (default 1 = newest pod)", required = false) Integer sampleN) {
        logger.info("MCP threadDump service={} sampleN={}", service, sampleN);
        return sensor.threadDump(service, sampleN == null ? 1 : sampleN);
    }

    @Tool(description = """
        Diagnose a request-path blocking call by sampling the JSON thread dump over time WHILE THE
        OPERATOR'S LOAD RUN IS FLOWING. The sensor drives no traffic. Use this for "why is latency
        high" on a virtual-thread app: a blocked request thread (Future.get on a virtual thread)
        exists only while requests are in flight, is invisible to the wall flame graph (a parked
        virtual thread unmounts) and is NOT in the JFR ring (JFR records ThreadPark only for
        platform threads) — sampling dumps under load catches it on any image, including CRaC.
        Returns status OK with aggregated thread facts (requestThreadsActive,
        requestThreadsBlockedInFutureGet, blockedInsideTransaction, requestThreadsWaitingForConnection
        and byState = PEAK concurrent across samples; topBlockingFrames counts summed), or BLOCKED
        with a reason when the request rate over the last minute is not above minRequestRate (ask
        the operator to start the load run and call again while it runs) or when no dump could be
        taken (sidecar not attached).""")
    public BlockingResult diagnoseBlocking(
        @ToolParam(description = SERVICE_PARAM) String service,
        @ToolParam(description = "how long to sample, seconds (default 20; clamped to 60)", required = false) Integer durationSec,
        @ToolParam(description = "thread-dump sampling interval in ms (default 500)", required = false) Integer intervalMs,
        @ToolParam(description = "guard: request rate rps over the last minute that counts as load flowing (e.g. 1)") double minRequestRate) {
        logger.info("MCP diagnoseBlocking service={} dur={}", service, durationSec);
        return sensor.diagnoseBlocking(service,
            durationSec == null ? 20 : durationSec,
            intervalMs == null ? 500L : intervalMs,
            minRequestRate);
    }

    @Tool(description = """
        Top hottest leaf frames for a Java service from Pyroscope, with self% shares. type=cpu gives
        jitShare and gcShare (% of all CPU self time); type=wall gives futexWallShare (% of all wall
        self time parked in futex/lock waits). Shares are over the whole profile, not only the frames
        returned. Use cpu to see JIT/class-loading dominance (startup), wall to see off-CPU blocking
        (latency). Returns frames, the relevant share, and the sample count for the window.""")
    public ProfileTop profileTop(
        @ToolParam(description = SERVICE_PARAM) String service,
        @ToolParam(description = "profile type: cpu or wall") String type,
        @ToolParam(description = "Look-back window in minutes (default 15)", required = false) Integer windowMinutes,
        @ToolParam(description = "max frames to return (default 15)", required = false) Integer limit) {
        logger.info("MCP profileTop service={} type={}", service, type);
        return sensor.profileTop(service, type, orDefault(windowMinutes), limit == null ? 15 : limit);
    }

    @Tool(description = """
        The last startup line from the app container log: {pod, line, seconds, kind} where kind is
        Started (cold start) or Restored (CRaC checkpoint restore). Complements the measured startup
        seconds and verifies a CRaC restore. Spring Boot log format; returns nulls if no line is present.""")
    public StartupResult startupLog(
        @ToolParam(description = SERVICE_PARAM) String service) {
        logger.info("MCP startupLog service={}", service);
        return sensor.startupLog(service);
    }

    private static int orDefault(Integer windowMinutes) {
        return windowMinutes == null || windowMinutes <= 0 ? 15 : windowMinutes;
    }
}
