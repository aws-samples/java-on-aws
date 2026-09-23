package com.example.perf.sensor;

import com.example.perf.sensor.collect.K8sCollector;
import com.example.perf.sensor.collect.K8sCollector.ProfiledPod;
import com.example.perf.sensor.collect.LogCollector;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.MultiGauge;
import io.micrometer.core.instrument.Tags;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Publishes every profiled workload's startup time as a scraped Prometheus gauge —
 * {@code perf_sensor_startup_seconds{service,namespace,pod}} — read from each Ready pod's
 * log ({@code Started}/{@code Restored} … seconds). This is the only reliable source of a
 * CRaC restore time: {@code application_ready_time_seconds} is baked into the checkpoint
 * and never refreshes on restore.
 *
 * <p>Workloads are discovered by the profiler opt-in label ({@code PROFILED_POD_LABEL},
 * default {@code perf-profile/sidecar=true}), so one sensor serves every opted-in service
 * in the cluster. Startup is a per-pod constant: the log is read once per pod and cached;
 * the poll only lists pods and re-reads when a new pod appears. {@link MultiGauge#register}
 * rebuilds the rows each cycle, so gone pods drop automatically.
 */
@Component
public class StartupMetrics {

    private static final Logger logger = LoggerFactory.getLogger(StartupMetrics.class);

    private final K8sCollector k8s;
    private final LogCollector logs;
    private final MultiGauge gauge;
    private final String podLabelSelector;
    private final String sidecarName;
    // Per-pod cache (namespace/pod) of the parsed startup seconds, so a known pod's log is read once.
    private final Map<String, Double> byPod = new HashMap<>();

    public StartupMetrics(K8sCollector k8s, LogCollector logs, MeterRegistry registry,
                          @Value("${PROFILED_POD_LABEL:perf-profile/sidecar=true}") String podLabelSelector,
                          @Value("${PROFILER_CONTAINER:perf-profiler}") String sidecarName) {
        this.k8s = k8s;
        this.logs = logs;
        this.podLabelSelector = podLabelSelector;
        this.sidecarName = sidecarName;
        this.gauge = MultiGauge.builder("perf.sensor.startup.seconds")
            .description("App startup/restore time in seconds, read from the pod log (Started/Restored)")
            .baseUnit("seconds")
            .register(registry);
    }

    @Scheduled(initialDelay = 20_000, fixedDelay = 30_000)
    public void refresh() {
        try {
            List<ProfiledPod> pods = k8s.readyPodsByLabel(podLabelSelector, sidecarName);
            byPod.keySet().retainAll(pods.stream().map(StartupMetrics::key).toList());

            List<MultiGauge.Row<?>> rows = pods.stream()
                .<MultiGauge.Row<?>>map(p -> {
                    Double seconds = byPod.computeIfAbsent(key(p), k -> {
                        var line = logs.lastStartup(p.namespace(), p.pod(), p.appContainer());
                        return line == null ? null : line.seconds();
                    });
                    if (seconds == null) {
                        byPod.remove(key(p));   // retry next cycle if the line wasn't there yet
                        return null;
                    }
                    return MultiGauge.Row.of(
                        Tags.of("service", p.service(), "namespace", p.namespace(), "pod", p.pod()), seconds);
                })
                .filter(Objects::nonNull)
                .toList();

            gauge.register(rows, true);
        } catch (Exception e) {
            logger.warn("startup metric refresh failed: {}", e.getMessage());
        }
    }

    private static String key(ProfiledPod p) {
        return p.namespace() + "/" + p.pod();
    }
}
