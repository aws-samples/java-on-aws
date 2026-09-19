package com.example.perf.sensor.collect;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Parser tests for the sidecar /dump payloads — the pieces most likely to break on
 * a JVM/format change. GC.heap_info has no "committed" keyword for SerialGC, so
 * committed is summed from per-generation "total" (the bug this pins).
 */
class DumpParseTest {

    private final DumpCollector dump = new DumpCollector(9100, "com.example.app");

    @Test
    void heap_serialGc_sumsGenerationTotals_andReadsGcFromVmFlags() {
        String body = """
            DefNew     total 25920K, used 13546K [0x...)
             eden space 23040K,  58% used [0x...)
             from space 2880K,   3% used [0x...)
            Tenured    total 57528K, used 41247K [0x...)
             the  space 57528K,  71% used [0x...)

            -XX:InitialHeapSize=33554432 -XX:MaxHeapSize=536870912 -XX:+UseSerialGC -XX:+UseCompressedOops
            """;
        var heap = dump.parseHeap(body);
        assertThat(heap.gcName()).isEqualTo("SerialGC");
        // committed = 25920 + 57528 = 83448K = 81.49Mi ; used = 13546 + 41247 = 54793K = 53.5Mi
        assertThat(heap.heapCommittedMi()).isCloseTo(81.49, org.assertj.core.data.Offset.offset(0.1));
        assertThat(heap.heapUsedMi()).isCloseTo(53.5, org.assertj.core.data.Offset.offset(0.5));
    }

    @Test
    void heap_g1_detected() {
        var heap = dump.parseHeap("garbage-first heap   total 524288K, used 120000K\n-XX:+UseG1GC");
        assertThat(heap.gcName()).isEqualTo("G1GC");
        assertThat(heap.heapCommittedMi()).isCloseTo(512.0, org.assertj.core.data.Offset.offset(0.1));
    }

    @Test
    void threads_countsBlockingFutureGetOnRequestPath() throws Exception {
        // Two request-path threads (the app package); one parked in CompletableFuture.get.
        String json = """
            {"threadDump":{"threadContainers":[{"threads":[
              {"name":"http-nio-8080-exec-1","stack":[
                 "java.base/java.util.concurrent.CompletableFuture.get(CompletableFuture.java:2093)",
                 "com.example.app.Service.handle(Service.java:42)"]},
              {"name":"http-nio-8080-exec-2","stack":[
                 "com.example.app.Service.handle(Service.java:40)"]},
              {"name":"idle-scheduler","stack":["java.base/jdk.internal.misc.Unsafe.park(Unsafe.java:1)"]}
            ]}]}}
            """;
        var t = dump.parseThreads(json, "pod-x", "2026-01-01T00:00:00Z");
        assertThat(t.total()).isEqualTo(3);
        assertThat(t.requestThreadsBlockedInFutureGet()).isEqualTo(1);
        assertThat(t.topBlockingFrames()).isNotEmpty();
        assertThat(t.topBlockingFrames().getFirst().frame()).contains("CompletableFuture.get");
        assertThat(t.pod()).isEqualTo("pod-x");
    }

    @Test
    void threads_noBlocking_whenNoRequestPathFutureGet() throws Exception {
        String json = """
            {"threadDump":{"threadContainers":[{"threads":[
              {"name":"http-nio-8080-exec-1","stack":["com.example.app.Service.handle(Service.java:10)"]}
            ]}]}}
            """;
        var t = dump.parseThreads(json, "pod-y", "2026-01-01T00:00:00Z");
        assertThat(t.requestThreadsBlockedInFutureGet()).isZero();
    }
}
