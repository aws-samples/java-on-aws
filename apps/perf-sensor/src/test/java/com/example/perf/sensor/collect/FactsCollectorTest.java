package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.JfrFacts;
import com.example.perf.sensor.facts.ProfileFacts;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Window scoping rules: cAdvisor queries are scoped to the Ready pods; the floor and latency
 * exclude the pod's boot minute; CPU and throttling use the steady window (after readiness and
 * after the JIT settled) and report the mean over it minus the JIT compiler threads' share of the
 * CPU profile; the request rate is clipped to the pod's lifetime; and startup
 * prefers the log-derived gauge over application.ready.time.
 */
@ExtendWith(MockitoExtension.class)
class FactsCollectorTest {

    @Mock K8sCollector k8s;
    @Mock PrometheusClient prometheus;
    @Mock PyroscopeClient pyroscope;
    @Mock DumpCollector dump;
    @Mock JfrCollector jfr;

    private FactsCollector collector() {
        when(dump.heap(any())).thenReturn(DumpCollector.HeapInfo.empty());
        when(pyroscope.summarize(anyString(), anyString(), anyString(), anyInt()))
            .thenReturn(new ProfileFacts(List.of(), List.of(), null, null, null, 0));
        return new FactsCollector(k8s, prometheus, pyroscope, dump, jfr);
    }

    private static K8sCollector.Snapshot snap(Double uptime, List<String> ready) {
        return new K8sCollector.Snapshot(null, 0, "10.0.0.1", ready.isEmpty() ? null : ready.getFirst(),
            "shop", uptime, null, ready);
    }

    /** A JFR ring whose JIT was busy until {@code busySeconds} after the container started. */
    private static JfrFacts ringJitBusyUntil(double uptime, double busySeconds) {
        var busyUntil = Instant.now().minusMillis((long) ((uptime - busySeconds) * 1000));
        return new JfrFacts("p1", null, null, null, null, null, null, List.of(), null,
            new JfrFacts.Compilation(40, 9000.0, 300.0, busyUntil.toString()));
    }

    @Test
    void youngPod_hasNoFloorNoThrottleNoSteadyCpu_trafficWindowIsOneMinute() {
        when(prometheus.startupSeconds("shop")).thenReturn(null);   // startup unknown: boot minute + margin
        var f = collector().collect("shop", 15, snap(45.0, List.of("p1")));
        verify(prometheus, never()).workingSetFloorMi(any(), any(), any(), anyInt());
        verify(prometheus, never()).cpuThrottledRatio(any(), any(), any(), anyInt());
        verify(prometheus, never()).cpuUsageMeanCores(any(), any(), any(), anyInt());
        verify(pyroscope, never()).cpuJitShare(any(), any(), any());
        verify(prometheus).requestRatePerSec("shop", 1);
        verify(prometheus).latencyMeanMs("shop", 1);
        verify(prometheus).workingSetPeakMi("shop", "shop", "p1", 15);
        assertThat(f.runtime().workingSetFloorMi()).isNull();
        assertThat(f.runtime().cpuThrottledRatio()).isNull();
        assertThat(f.runtime().cpuSteadyCores()).isNull();
        assertThat(f.runtime().cpuMeanCores()).isNull();
    }

    @Test
    void freshColdPod_steadyIsTheMeanAfterReadinessMinusTheJit() {
        // startup 15 s: steady from 15 + 10 = 25 s; at 120 s that is 95 s. Mean 0.42 cores, of
        // which the compiler threads took 25 % -> 0.315 cores of load.
        when(prometheus.startupSeconds("shop")).thenReturn(15.0);
        when(prometheus.cpuUsageMeanCores("shop", "shop", "p1", 95)).thenReturn(0.42);
        when(pyroscope.cpuJitShare(eq("shop"), anyString(), anyString())).thenReturn(25.0);
        var f = collector().collect("shop", 15, snap(120.0, List.of("p1")));
        verify(prometheus).cpuThrottledRatio("shop", "shop", "p1", 95);
        assertThat(f.runtime().cpuMeanCores()).isEqualTo(0.42);
        assertThat(f.runtime().cpuJitShare()).isEqualTo(25.0);
        assertThat(f.runtime().cpuSteadyCores()).isEqualTo(0.315);
        assertThat(f.runtime().steadyStartSeconds()).isEqualTo(25.0);
        assertThat(f.runtime().steadyWindowSeconds()).isEqualTo(95);
    }

    @Test
    void busyJit_movesTheSteadyStartPastReadiness() {
        // JIT busy until 80 s, readiness at 25 s: steady from 80 s, 100 s at uptime 180 s.
        when(prometheus.startupSeconds("shop")).thenReturn(15.0);
        when(jfr.collect(any(), any())).thenReturn(ringJitBusyUntil(180.0, 80.0));
        var f = collector().collect("shop", 15, snap(180.0, List.of("p1")));
        verify(prometheus).cpuUsageMeanCores("shop", "shop", "p1", 100);
        verify(prometheus).cpuThrottledRatio("shop", "shop", "p1", 100);
        assertThat(f.runtime().steadyStartSeconds()).isBetween(79.0, 81.0);
    }

    @Test
    void jitBusyAlmostToNow_keepsASixtySecondWindow() {
        // four 15 s scrapes: a 30 s window held two and came back empty on a restored pod.
        when(prometheus.startupSeconds("shop")).thenReturn(15.0);
        when(jfr.collect(any(), any())).thenReturn(ringJitBusyUntil(120.0, 115.0));
        var f = collector().collect("shop", 15, snap(120.0, List.of("p1")));
        verify(prometheus).cpuUsageMeanCores("shop", "shop", "p1", 60);
        assertThat(f.runtime().steadyStartSeconds()).isEqualTo(60.0);
    }

    @Test
    void coldPodLessThanAMinutePastReadiness_hasNoSteadyCpu() {
        // ready at 25 s, uptime 80 s: 55 s of steady state, under the 60 s minimum.
        when(prometheus.startupSeconds("shop")).thenReturn(15.0);
        var f = collector().collect("shop", 15, snap(80.0, List.of("p1")));
        verify(prometheus, never()).cpuUsageMeanCores(any(), any(), any(), anyInt());
        assertThat(f.runtime().cpuSteadyCores()).isNull();
        assertThat(f.runtime().steadyStartSeconds()).isNull();
    }

    @Test
    void restoredPod_hasNoBootToExclude() {
        // CRaC restore in 0.06 s: steady from 10.06 s, 109 s at uptime 120 s.
        when(prometheus.startupSeconds("shop")).thenReturn(0.06);
        collector().collect("shop", 15, snap(120.0, List.of("p1")));
        verify(prometheus).cpuUsageMeanCores("shop", "shop", "p1", 109);
    }

    @Test
    void settledPod_cpuIsTheMeanOverTheWholeSteadyWindow() {
        when(prometheus.startupSeconds("shop")).thenReturn(null);
        collector().collect("shop", 15, snap(600.0, List.of("p1", "p2")));
        // no startup known: steady from 60 + 10 = 70 s -> 530 s; throttle capped at 300 s.
        // Floor and latency: (600-60)/60 = 9 min.
        verify(prometheus).cpuUsageMeanCores("shop", "shop", "p1|p2", 530);
        verify(prometheus).cpuThrottledRatio("shop", "shop", "p1|p2", 300);
        verify(prometheus).workingSetFloorMi("shop", "shop", "p1|p2", 9);
        verify(prometheus).latencyMeanMs("shop", 9);
        verify(prometheus).latencyMaxMs("shop", 9);
        verify(prometheus).requestRatePerSec("shop", 10);
    }

    @Test
    void oldPod_windowsAreTheRequestedWindow() {
        collector().collect("shop", 15, snap(3600.0, List.of("p1")));
        verify(prometheus).workingSetFloorMi("shop", "shop", "p1", 15);
        verify(prometheus).cpuUsageMeanCores("shop", "shop", "p1", 900);
        verify(prometheus).latencyMeanMs("shop", 15);
        verify(prometheus).requestRatePerSec("shop", 15);
        verify(prometheus).cpuThrottledRatio("shop", "shop", "p1", 300);
    }

    @Test
    void withoutJit_subtractsTheShare_keepsTheMeanWithoutAProfile() {
        assertThat(FactsCollector.withoutJit(0.40, 30.0)).isEqualTo(0.28);
        assertThat(FactsCollector.withoutJit(0.40, null)).isEqualTo(0.40);
        assertThat(FactsCollector.withoutJit(null, 30.0)).isNull();
        assertThat(FactsCollector.withoutJit(0.40, 0.0)).isEqualTo(0.40);
    }

    @Test
    void startup_prefersTheLogGauge_thenReadyTime_restrictedToCurrentPods() {
        var c = new FactsCollector(k8s, prometheus, pyroscope, dump, jfr);
        when(prometheus.perPodStartupFromLog("shop")).thenReturn(Map.of("old", 14.0, "p1", 0.06));
        when(prometheus.perPodStartup("shop")).thenReturn(Map.of("p1", 13.0, "p2", 12.5));
        assertThat(c.currentStartup("shop", List.of("p1"))).isEqualTo(0.06);
        assertThat(c.perPodStartup("shop", List.of("p1", "p2")))
            .containsEntry("p1", 0.06).containsEntry("p2", 12.5).doesNotContainKey("old");
    }

    @Test
    void startup_fallsBackToFleetMax_withoutReadyPods() {
        var c = new FactsCollector(k8s, prometheus, pyroscope, dump, jfr);
        when(prometheus.startupSeconds("shop")).thenReturn(9.0);
        assertThat(c.currentStartup("shop", List.of())).isEqualTo(9.0);
        verify(prometheus, never()).perPodStartupFromLog(eq("shop"));
    }
}
