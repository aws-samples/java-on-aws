package com.example.perf.optimizer.facts;

import java.util.HashMap;
import java.util.Map;

/**
 * The complete typed fact set for one service, aggregated from all collectors.
 * Any sub-facts may be null when a source is unavailable; the evaluator degrades
 * gracefully (findings gated on a missing fact become NOT_EVALUABLE).
 *
 * <p>{@link #toContext()} flattens the facts into the nested map the catalog SpEL
 * expressions read (e.g. {@code limits.memory}, {@code rss.peak},
 * {@code profile.warmupWindow}). Memory is MiB, CPU is cores, startup is seconds —
 * so detectors read as plain arithmetic.
 */
public record Facts(
    WorkloadFacts workload,
    RuntimeFacts runtime,
    ProfileFacts profile,
    ThreadFacts threads
) {

    /** Build the nested variable map consumed by the catalog SpEL expressions. */
    public Map<String, Object> toContext() {
        var ctx = new HashMap<String, Object>();
        var cpu = new HashMap<String, Object>();

        if (workload != null) {
            ctx.put("limits", map("memory", workload.memLimitMi(), "cpu", workload.cpuLimitCores()));
            ctx.put("requests", map("memory", workload.memRequestMi(), "cpu", workload.cpuRequestCores()));
            ctx.put("image", workload.imageTag());
            ctx.put("resizePolicy", workload.cpuResizePolicy());
            ctx.put("replicas", workload.replicas());
            ctx.put("sidecars", map("present", workload.sidecarsPresent()));
            ctx.put("namespace", workload.namespace());
            ctx.put("deployment", workload.deployment());
            cpu.put("limit", workload.cpuLimitCores());
            cpu.put("request", workload.cpuRequestCores());
        }
        if (runtime != null) {
            ctx.put("rss", map("floor", runtime.rssFloorMi(), "peak", runtime.rssPeakMi()));
            ctx.put("heap", map("used", runtime.heapUsedMi(), "committed", runtime.heapCommittedMi()));
            ctx.put("gc", runtime.gcName());
            ctx.put("startup", runtime.startupSeconds());
            ctx.put("restarts", runtime.restarts());
            ctx.put("uptime", runtime.uptimeSeconds());
            ctx.put("requestRate", runtime.requestRatePerSec());
            cpu.put("effective", runtime.effectiveCpuCount());
        }
        ctx.put("cpu", cpu);
        if (profile != null) {
            ctx.put("profile", map(
                "warmupWindow", profile.warmupWindow(),
                "jitShare", profile.jitSharePct(),
                "gcShare", profile.gcSharePct(),
                "futexWallShare", profile.futexWallSharePct()));
            ctx.put("samples", profile.samples());
        } else {
            ctx.put("profile", map("warmupWindow", null, "jitShare", null, "gcShare", null, "futexWallShare", null));
            ctx.put("samples", 0L);
        }
        if (threads != null) {
            ctx.put("threads", map(
                "futureGetOnRequestPath", threads.futureGetOnRequestPath(),
                "poolWaitCarriers", threads.poolWaitCarriers()));
        } else {
            ctx.put("threads", map("futureGetOnRequestPath", null, "poolWaitCarriers", null));
        }
        return ctx;
    }

    /**
     * Resolve a dotted fact path (e.g. {@code "rss.peak"}) against {@link #toContext()},
     * returning the leaf value or null when any segment is absent/null. Used by the
     * evaluator to enforce a finding's {@code requires} list.
     */
    public Object resolve(String path) {
        return resolve(toContext(), path);
    }

    @SuppressWarnings("unchecked")
    public static Object resolve(Map<String, Object> ctx, String path) {
        Object cur = ctx;
        for (var seg : path.split("\\.")) {
            if (!(cur instanceof Map<?, ?> m)) {
                return null;
            }
            cur = ((Map<String, Object>) m).get(seg);
            if (cur == null) {
                return null;
            }
        }
        return cur;
    }

    private static Map<String, Object> map(Object... kv) {
        var m = new HashMap<String, Object>();
        for (int i = 0; i + 1 < kv.length; i += 2) {
            m.put((String) kv[i], kv[i + 1]);
        }
        return m;
    }
}
