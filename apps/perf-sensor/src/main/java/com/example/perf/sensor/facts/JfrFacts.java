package com.example.perf.sensor.facts;

import java.util.List;

/**
 * Facts parsed from the app JVM's own JFR ring (recording "perf", maxage 10 min, started
 * by the profiler sidecar via jcmd). This is the only RETROSPECTIVE, in-JVM source: what
 * happened inside the JVM over the last minutes whether or not anyone was watching.
 * NOTE: JFR does not record jdk.ThreadPark for VIRTUAL threads (verified on JDK 25), so a
 * request-path block on a virtual-thread app is NOT in this ring — that needs a live JSON
 * thread dump under load ({@code diagnoseBlocking}). Any field may be null when the ring
 * is unavailable or an event type recorded nothing.
 *
 * @param pod              pod the ring was dumped from
 * @param recordingStart   first event timestamp in the dump (ISO-8601)
 * @param recordingEnd     last event timestamp in the dump (ISO-8601)
 * @param container        jdk.ContainerConfiguration — limits as the JVM read them
 * @param jvmArgs          jdk.JVMInformation.jvmArguments (flags incl. ENTRYPOINT/JAVA_TOOL_OPTIONS)
 * @param gc               jdk.GCPhasePause aggregate
 * @param pinned           jdk.VirtualThreadPinned aggregate (synchronized blocks pinning carriers)
 * @param monitorTop       jdk.JavaMonitorEnter top monitors by total blocked time, with the waiting frame
 * @param safepointTotalMs jdk.SafepointBegin total stop-the-world time, ms
 * @param compilation      jdk.Compilation aggregate (JIT volume in the window)
 */
public record JfrFacts(
    String pod,
    String recordingStart,
    String recordingEnd,
    ContainerConfig container,
    String jvmArgs,
    GcPauses gc,
    Pinned pinned,
    List<MonitorWait> monitorTop,
    Double safepointTotalMs,
    Compilation compilation
) {
    /** jdk.ContainerConfiguration: effectiveCpuCount is what the JVM sizes GC/JIT threads from. */
    public record ContainerConfig(Integer effectiveCpuCount, Double cpuQuotaCores, Double memoryLimitMi,
                                  String containerType) {}

    /** jdk.GCPhasePause: count, max and total pause over the ring. */
    public record GcPauses(int count, Double maxMs, Double totalMs, String longestName) {}

    /** jdk.VirtualThreadPinned: count, max duration, top pinning frames. */
    public record Pinned(int count, Double maxMs, List<FrameCount> topFrames) {}

    /** {@code topFrame}: the most frequent frame of the threads that waited (first app frame if any). */
    public record MonitorWait(String monitorClass, int count, Double totalMs, String topFrame) {}

    public record Compilation(int count, Double totalMs, Double maxMs) {}

    public record FrameCount(String frame, int count) {}
}
