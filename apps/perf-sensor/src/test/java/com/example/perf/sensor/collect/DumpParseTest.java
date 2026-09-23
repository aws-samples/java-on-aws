package com.example.perf.sensor.collect;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;

/**
 * Parser tests for the sidecar /dump payloads — the pieces most likely to break on a
 * JVM/format change. GC.heap_info has no "committed" keyword for SerialGC, so committed is
 * summed from per-generation "total" (the bug this pins). A body that is not a JSON thread
 * dump must throw, so the caller reports UNKNOWN instead of "0 blocked".
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
        assertThat(heap.heapCommittedMi()).isCloseTo(81.49, within(0.1));
        assertThat(heap.heapUsedMi()).isCloseTo(53.5, within(0.5));
        // observed heap bounds from VM.flags (bytes -> MiB)
        assertThat(heap.maxHeapMi()).isEqualTo(512.0);
        assertThat(heap.initialHeapMi()).isEqualTo(32.0);
    }

    @Test
    void heap_g1_detected() {
        var heap = dump.parseHeap("garbage-first heap   total 524288K, used 120000K\n-XX:+UseG1GC");
        assertThat(heap.gcName()).isEqualTo("G1GC");
        assertThat(heap.heapCommittedMi()).isCloseTo(512.0, within(0.1));
    }

    @Test
    void threads_countsBlockingFutureGetOnRequestPath() {
        // Two request-path threads (the app package); one parked in CompletableFuture.get.
        String json = """
            {"threadDump":{"threadContainers":[{"threads":[
              {"name":"tomcat-handler-1","state":"WAITING","stack":[
                 "java.base/java.util.concurrent.CompletableFuture.get(CompletableFuture.java:2093)",
                 "com.example.app.Service.handle(Service.java:42)"]},
              {"name":"tomcat-handler-2","state":"RUNNABLE","stack":[
                 "com.example.app.Service.handle(Service.java:40)"]},
              {"name":"idle-scheduler","state":"WAITING","stack":["java.base/jdk.internal.misc.Unsafe.park(Unsafe.java:1)"]}
            ]}]}}
            """;
        var t = dump.parseThreads(json, "pod-x", "2026-01-01T00:00:00Z");
        assertThat(t.total()).isEqualTo(3);
        assertThat(t.requestThreadsActive()).isEqualTo(2);
        assertThat(t.requestThreadsBlockedInFutureGet()).isEqualTo(1);
        assertThat(t.topBlockingFrames()).isNotEmpty();
        assertThat(t.topBlockingFrames().getFirst().frame()).contains("CompletableFuture.get");
        assertThat(t.byState()).containsEntry("WAITING", 2).containsEntry("RUNNABLE", 1);
        assertThat(t.pod()).isEqualTo("pod-x");
    }

    @Test
    void threads_noBlocking_whenNoRequestPathFutureGet() {
        String json = """
            {"threadDump":{"threadContainers":[{"threads":[
              {"name":"tomcat-handler-1","stack":["com.example.app.Service.handle(Service.java:10)"]}
            ]}]}}
            """;
        var t = dump.parseThreads(json, "pod-y", "2026-01-01T00:00:00Z");
        assertThat(t.requestThreadsBlockedInFutureGet()).isZero();
        assertThat(t.blockedInsideTransaction()).isZero();
    }

    @Test
    void threads_countsBlockingInsideTransaction() {
        // Blocked in Future.get with Spring's transaction interceptor below on the stack:
        // the remote round-trip is held inside the DB transaction (connection held).
        String json = """
            {"threadDump":{"threadContainers":[{"threads":[
              {"name":"tomcat-handler-7","virtual":true,"stack":[
                 "java.base/java.util.concurrent.CompletableFuture.get(CompletableFuture.java:2093)",
                 "com.example.app.Service.publish(Service.java:126)",
                 "com.example.app.Service.create(Service.java:42)",
                 "org.springframework.transaction.interceptor.TransactionAspectSupport.invokeWithinTransaction(TransactionAspectSupport.java:380)",
                 "org.springframework.transaction.interceptor.TransactionInterceptor.invoke(TransactionInterceptor.java:119)"]},
              {"name":"tomcat-handler-8","virtual":true,"stack":[
                 "java.base/java.util.concurrent.CompletableFuture.get(CompletableFuture.java:2093)",
                 "com.example.app.Service.notify(Service.java:200)"]}
            ]}]}}
            """;
        var t = dump.parseThreads(json, "pod-z", "2026-01-01T00:00:00Z");
        assertThat(t.requestThreadsBlockedInFutureGet()).isEqualTo(2);
        assertThat(t.blockedInsideTransaction()).isEqualTo(1);
        assertThat(t.requestThreadsActive()).isEqualTo(2);
        assertThat(t.virtualThreads()).isEqualTo(2);
    }

    @Test
    void threads_poolWaitNeedsAWaitingStateInsideBorrow() {
        String json = """
            {"threadDump":{"threadContainers":[{"threads":[
              {"name":"tomcat-handler-1","state":"TIMED_WAITING","stack":[
                 "java.base/jdk.internal.misc.Unsafe.park(Unsafe.java:1)",
                 "com.zaxxer.hikari.util.ConcurrentBag.borrow(ConcurrentBag.java:151)",
                 "com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:160)",
                 "com.example.app.Repo.save(Repo.java:20)"]},
              {"name":"tomcat-handler-2","state":"RUNNABLE","stack":[
                 "com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:150)",
                 "com.example.app.Repo.save(Repo.java:20)"]},
              {"name":"tomcat-handler-3","state":"TIMED_WAITING","stack":[
                 "com.zaxxer.hikari.util.ConcurrentBag.borrow(ConcurrentBag.java:151)",
                 "some.other.Batch.run(Batch.java:1)"]}
            ]}]}}
            """;
        var t = dump.parseThreads(json, "pod-p", "2026-01-01T00:00:00Z");
        // 1: waiting inside borrow on the request path -> counted
        // 2: RUNNABLE, merely passing through getConnection -> not a wait
        // 3: waiting in borrow but not on the request path -> not counted
        assertThat(t.requestThreadsWaitingForConnection()).isEqualTo(1);
        assertThat(t.requestThreadsActive()).isEqualTo(2);
    }

    @Test
    void threads_notAJsonDump_throws_soTheCallerReportsUnknown() {
        // JSON without the dump structure (e.g. an error envelope)
        assertThatThrownBy(() -> dump.parseThreads("{\"fallback\":\"Thread.print\",\"note\":\"jcmd failed\"}", "pod", "t"))
            .isInstanceOf(IllegalArgumentException.class);
        // not JSON at all (a Thread.print text dump)
        assertThatThrownBy(() -> dump.parseThreads("Full thread dump OpenJDK 64-Bit Server VM", "pod", "t"));
    }

    @Test
    void requestPackageIsRequired() {
        assertThatThrownBy(() -> new DumpCollector(9100, ""))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("REQUEST_PACKAGE");
    }
}
