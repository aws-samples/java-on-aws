package com.example.perf.sensor.collect;

import com.example.perf.sensor.facts.ProfileFacts;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

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
 * Window scoping rules: cAdvisor queries are scoped to the Ready pods; the floor, CPU p95,
 * latency and throttle ratio exclude the pod's boot minute; the request rate is clipped to the
 * pod's lifetime; and startup prefers the log-derived gauge over application.ready.time.
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

    @Test
    void youngPod_hasNoFloorAndNoThrottleRatio_trafficWindowIsOneMinute() {
        var f = collector().collect("shop", 15, snap(45.0, List.of("p1")));
        verify(prometheus, never()).workingSetFloorMi(any(), any(), any(), anyInt());
        verify(prometheus, never()).cpuThrottledRatio(any(), any(), any(), anyInt());
        verify(prometheus).requestRatePerSec("shop", 1);
        verify(prometheus).latencyMeanMs("shop", 1);
        verify(prometheus).workingSetPeakMi("shop", "shop", "p1", 15);
        verify(prometheus).cpuUsageP95Cores("shop", "shop", "p1", 15);
        assertThat(f.runtime().workingSetFloorMi()).isNull();
        assertThat(f.runtime().cpuThrottledRatio()).isNull();
    }

    @Test
    void settledPod_floorAndThrottleExcludeTheBootMinute_windowsClipToUptime() {
        collector().collect("shop", 15, snap(600.0, List.of("p1", "p2")));
        // floor, cpu p95, latency: (600 - 60) / 60 = 9 min; throttle: min(300, 600 - 60) = 300 s;
        // request rate: lifetime, 10 min
        verify(prometheus).workingSetFloorMi("shop", "shop", "p1|p2", 9);
        verify(prometheus).cpuUsageP95Cores("shop", "shop", "p1|p2", 9);
        verify(prometheus).latencyMeanMs("shop", 9);
        verify(prometheus).latencyMaxMs("shop", 9);
        verify(prometheus).cpuThrottledRatio("shop", "shop", "p1|p2", 300);
        verify(prometheus).requestRatePerSec("shop", 10);
    }

    @Test
    void oldPod_windowsAreTheRequestedWindow() {
        collector().collect("shop", 15, snap(3600.0, List.of("p1")));
        verify(prometheus).workingSetFloorMi("shop", "shop", "p1", 15);
        verify(prometheus).cpuUsageP95Cores("shop", "shop", "p1", 15);
        verify(prometheus).latencyMeanMs("shop", 15);
        verify(prometheus).requestRatePerSec("shop", 15);
        verify(prometheus).cpuThrottledRatio("shop", "shop", "p1", 300);
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
