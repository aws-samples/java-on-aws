package com.example.perf.sensor;

import com.example.perf.sensor.collect.K8sCollector;
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
 * Publishes the workload's startup time as a scraped Prometheus gauge —
 * {@code perf_sensor_startup_seconds{service,pod}} — read from each Ready pod's log
 * ({@code Started}/{@code Restored} … seconds), which is the ONLY reliable source of
 * CRaC restore time: {@code application_ready_time_seconds} is baked into the CRaC
 * checkpoint and never refreshes on restore.
 *
 * <p>Startup is a per-pod constant, so the log is read once per pod and cached; the
 * poll only checks Ready-pod identity (a cheap K8s list) and re-reads a pod's log
 * when a new pod appears (a rollout). {@link MultiGauge#register} rebuilds the rows
 * each cycle, so gone pods drop automatically. Prometheus scraping the sensor turns
 * the held values into the dashboard timeseries.
 */
@Component
public class StartupMetrics {

    private static final Logger logger = LoggerFactory.getLogger(StartupMetrics.class);

    private final K8sCollector k8s;
    private final LogCollector logs;
    private final MultiGauge gauge;
    private final String service;   // namespace == service == container by convention
    // Per-pod cache of the parsed startup seconds, so a known pod's log is read once.
    private final Map<String, Double> byPod = new HashMap<>();

    public StartupMetrics(K8sCollector k8s, LogCollector logs, MeterRegistry registry,
                          @Value("${STARTUP_METRIC_SERVICE:unicorn-store-spring}") String service) {
        this.k8s = k8s;
        this.logs = logs;
        this.service = service;
        this.gauge = MultiGauge.builder("perf.sensor.startup.seconds")
            .description("App startup/restore time in seconds, read from the pod log (Started/Restored)")
            .baseUnit("seconds")
            .register(registry);
    }

    @Scheduled(initialDelay = 20_000, fixedDelay = 30_000)
    public void refresh() {
        try {
            List<K8sCollector.PodRef> refs = k8s.readyPodRefs(service, service);
            // Drop cache entries for pods no longer Ready.
            byPod.keySet().retainAll(refs.stream().map(K8sCollector.PodRef::name).toList());

            List<MultiGauge.Row<?>> rows = refs.stream()
                .<MultiGauge.Row<?>>map(r -> {
                    // Read the log only for pods we haven't parsed yet (per-pod constant).
                    Double seconds = byPod.computeIfAbsent(r.name(), name -> {
                        var line = logs.lastStartup(service, name, service);
                        return line == null ? null : line.seconds();
                    });
                    if (seconds == null) {
                        byPod.remove(r.name());   // retry next cycle if the line wasn't there yet
                        return null;
                    }
                    return MultiGauge.Row.of(Tags.of("service", service, "pod", r.name()), seconds);
                })
                .filter(Objects::nonNull)
                .toList();

            gauge.register(rows, true);
        } catch (Exception e) {
            logger.warn("startup metric refresh failed for service={}: {}", service, e.getMessage());
        }
    }
}
