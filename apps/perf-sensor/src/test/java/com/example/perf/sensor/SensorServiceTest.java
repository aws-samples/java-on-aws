package com.example.perf.sensor;

import com.example.perf.sensor.collect.DumpCollector;
import com.example.perf.sensor.collect.FactsCollector;
import com.example.perf.sensor.collect.K8sCollector;
import com.example.perf.sensor.collect.LogCollector;
import com.example.perf.sensor.collect.PrometheusClient;
import com.example.perf.sensor.collect.PyroscopeClient;
import com.example.perf.sensor.facts.ThreadFacts;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The aggregation and guard logic of the thread-dump tools, with the collectors mocked.
 * What matters: a dump that cannot be taken is UNKNOWN (null / BLOCKED), never a false
 * "nothing is blocked"; over time counters are peaks and frames are sums; over pods
 * counters are sums.
 */
@ExtendWith(MockitoExtension.class)
class SensorServiceTest {

    @Mock FactsCollector facts;
    @Mock K8sCollector k8s;
    @Mock PrometheusClient prometheus;
    @Mock PyroscopeClient pyroscope;
    @Mock DumpCollector dump;
    @Mock LogCollector logs;

    private SensorService sensor() {
        return new SensorService(facts, k8s, prometheus, pyroscope, dump, logs);
    }

    private static ThreadFacts dumpOf(String pod, int active, int blocked, int pool, int inTx,
                                      Map<String, Integer> byState, String frame, int hits) {
        return new ThreadFacts(pod, "t", 40, byState, 30, active, blocked, pool, inTx,
            frame == null ? List.of() : List.of(new ThreadFacts.FrameCount(frame, hits)), List.of());
    }

    private static K8sCollector.Snapshot snapshot(String pod, String ip) {
        return new K8sCollector.Snapshot(null, 0, ip, pod, "app", 600.0, null, List.of(pod));
    }

    @Test
    void diagnoseBlocking_isBlockedWithoutLoad_andTakesNoDump() {
        when(prometheus.requestRatePerSec("svc", 1)).thenReturn(0.4);
        var r = sensor().diagnoseBlocking("svc", 20, 500, 1);
        assertThat(r.status()).isEqualTo("BLOCKED");
        assertThat(r.reason()).contains("no load flowing");
        assertThat(r.threads()).isNull();
        verify(dump, never()).threads(anyString(), anyString());
    }

    @Test
    void diagnoseBlocking_isBlockedWhenNoDumpCanBeTaken() {
        when(prometheus.requestRatePerSec("svc", 1)).thenReturn(50.0);
        when(k8s.collect("svc", "svc")).thenReturn(snapshot("p1", "10.0.0.1"));
        when(dump.threads("10.0.0.1", "p1")).thenReturn(null);
        var r = sensor().diagnoseBlocking("svc", 3, 1000, 1);
        assertThat(r.status()).isEqualTo("BLOCKED");
        assertThat(r.reason()).contains("no thread dump");
        assertThat(r.threads()).isNull();
    }

    @Test
    void diagnoseBlocking_overTime_countersArePeaks_framesAreSums() {
        when(prometheus.requestRatePerSec("svc", 1)).thenReturn(50.0);
        when(k8s.collect("svc", "svc")).thenReturn(snapshot("p1", "10.0.0.1"));
        when(dump.threads("10.0.0.1", "p1")).thenReturn(
            dumpOf("p1", 3, 1, 2, 1, Map.of("RUNNABLE", 5, "WAITING", 20), "CompletableFuture.get", 1),
            dumpOf("p1", 2, 0, 0, 0, Map.of("RUNNABLE", 7, "WAITING", 18), null, 0),
            dumpOf("p1", 4, 2, 1, 2, Map.of("RUNNABLE", 6, "WAITING", 21), "CompletableFuture.get", 2));
        var r = sensor().diagnoseBlocking("svc", 3, 1000, 1);   // 3 s / 1000 ms = 3 samples
        assertThat(r.status()).isEqualTo("OK");
        var t = r.threads();
        assertThat(t.requestThreadsActive()).isEqualTo(4);
        assertThat(t.requestThreadsBlockedInFutureGet()).isEqualTo(2);
        assertThat(t.requestThreadsWaitingForConnection()).isEqualTo(2);
        assertThat(t.blockedInsideTransaction()).isEqualTo(2);
        assertThat(t.total()).isEqualTo(40);                       // peak, not 120
        assertThat(t.byState()).containsEntry("RUNNABLE", 7).containsEntry("WAITING", 21);
        assertThat(t.topBlockingFrames()).containsExactly(new ThreadFacts.FrameCount("CompletableFuture.get", 3));
    }

    @Test
    void threadDump_acrossPods_countersAreSums() {
        when(k8s.readyPodRefs("svc", "svc")).thenReturn(List.of(
            new K8sCollector.PodRef("p1", "10.0.0.1"), new K8sCollector.PodRef("p2", "10.0.0.2")));
        when(dump.threads("10.0.0.1", "p1")).thenReturn(dumpOf("p1", 2, 1, 0, 1, Map.of("RUNNABLE", 5), "F.get", 1));
        when(dump.threads("10.0.0.2", "p2")).thenReturn(dumpOf("p2", 3, 0, 1, 0, Map.of("RUNNABLE", 4), null, 0));
        var t = sensor().threadDump("svc", 2);
        assertThat(t.pod()).isEqualTo("p1,p2");
        assertThat(t.requestThreadsActive()).isEqualTo(5);
        assertThat(t.requestThreadsBlockedInFutureGet()).isEqualTo(1);
        assertThat(t.requestThreadsWaitingForConnection()).isEqualTo(1);
        assertThat(t.total()).isEqualTo(80);
        assertThat(t.byState()).containsEntry("RUNNABLE", 9);
    }

    @Test
    void threadDump_returnsNullWhenEveryDumpFails() {
        when(k8s.readyPodRefs("svc", "svc")).thenReturn(List.of(new K8sCollector.PodRef("p1", "10.0.0.1")));
        when(dump.threads(any(), any())).thenReturn(null);
        assertThat(sensor().threadDump("svc", 1)).isNull();
    }

    @Test
    void measure_doesNotWaitWhenNoLoadFlows_andSaysWhy() {
        var young = new K8sCollector.Snapshot(null, 0, "10.0.0.1", "p1", "app", 20.0, null, List.of("p1"));
        when(k8s.collect("svc", "svc")).thenReturn(young);
        when(prometheus.requestRatePerSec("svc", 1)).thenReturn(0.5);
        when(facts.collect(eq("svc"), eq(15), any())).thenReturn(
            new com.example.perf.sensor.facts.Facts(null, null, null, null));
        when(prometheus.perPodPeakMi(any(), any(), any(), eq(15))).thenReturn(Map.of());
        when(facts.perPodStartup("svc", List.of("p1"))).thenReturn(Map.of());
        var r = sensor().measure("svc", 15, 120);
        assertThat(r.window().waitedSeconds()).isZero();
        assertThat(r.window().settleRemainingSeconds()).isZero();
        assertThat(r.window().settleNote()).contains("no load is flowing");
    }
}
