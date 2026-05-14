package com.example.perf.analyzer;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Tags;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Computes and publishes per-service-version CPU ratios from Pyroscope as
 * Prometheus gauges. Fills the gap left by Pyroscope OSS lacking native
 * recording rules — Grafana alerts on the gauge this exporter emits.
 *
 * How it works, every {@value #REFRESH_INTERVAL_MS} ms:
 *   1. Ask {@link PyroscopeVersionService} which services have recent data.
 *   2. For each service, list its versions sorted by latest-sample timestamp.
 *   3. The newest version is the current candidate; the one below it is the
 *      baseline. Compute {@code ratio = current.total / baseline.total} and
 *      publish as {@code perf_profile_cpu_ratio{service_name, version}}.
 *
 * Services with only one version have no baseline yet — we skip them so no
 * stale gauge fires an alert on cold starts.
 */
@Component
public class ProfileRatioExporter {

    private static final Logger logger = LoggerFactory.getLogger(ProfileRatioExporter.class);

    private static final long REFRESH_INTERVAL_MS = 15_000L;    // 15s — demo-friendly
    private static final long COMPARE_WINDOW_SECONDS = 300L;    // 5 min — covers baseline→deploy→v2 load
    private static final String METRIC_NAME = "perf_profile_cpu_ratio";

    private final PyroscopeVersionService versions;
    private final MeterRegistry meterRegistry;

    /** Keeps the most recent ratio per (service, version) so the gauge stays live. */
    private final Map<GaugeKey, AtomicReference<Double>> ratios = new ConcurrentHashMap<>();

    public ProfileRatioExporter(PyroscopeVersionService versions, MeterRegistry meterRegistry) {
        this.versions = versions;
        this.meterRegistry = meterRegistry;
    }

    @Scheduled(fixedDelay = REFRESH_INTERVAL_MS, initialDelay = 5_000L)
    public void refresh() {
        try {
            var services = versions.listServiceNames();
            logger.info("ProfileRatioExporter: {} services to scan: {}", services.size(), services);
            for (var service : services) {
                try {
                    computeRatiosForService(service);
                } catch (Exception e) {
                    logger.warn("Ratio compute failed for service={}: {}", service, e.getMessage());
                }
            }
        } catch (Exception e) {
            logger.warn("ProfileRatioExporter refresh failed: {}", e.getMessage());
        }
    }

    private void computeRatiosForService(String service) {
        var totals = versions.recentVersionTotals(service, COMPARE_WINDOW_SECONDS);
        if (totals.isEmpty()) return;

        if (totals.size() < 2) {
            // One version only — no baseline yet. Also clear any stale gauge
            // left over from when we had multiple versions (a version retiring
            // out of the window should not leave its ratio firing).
            clearGaugesForService(service);
            logger.info("service={} has only one version ({}); skipping ratio",
                service, totals.get(0).version());
            return;
        }

        var current = totals.get(0);
        var baseline = totals.get(1);

        if (baseline.totalNanos() <= 0) {
            logger.debug("service={} baseline version={} has zero total; skipping",
                service, baseline.version());
            return;
        }

        double ratio = (double) current.totalNanos() / baseline.totalNanos();
        publishGauge(service, current.version(), ratio);

        logger.info("ratio service={} current={}({}ns) baseline={}({}ns) = {}",
            service, current.version(), current.totalNanos(),
            baseline.version(), baseline.totalNanos(),
            String.format("%.3f", ratio));
    }

    private void publishGauge(String service, String version, double ratio) {
        var key = new GaugeKey(service, version);
        var ref = ratios.computeIfAbsent(key, k -> {
            var holder = new AtomicReference<>(ratio);
            Gauge.builder(METRIC_NAME, holder, AtomicReference::get)
                .description("Ratio of current-version CPU self-time vs previous-version baseline")
                .tags(Tags.of("service_name", k.service(), "version", k.version()))
                .register(meterRegistry);
            return holder;
        });
        ref.set(ratio);
    }

    /**
     * Drop gauges for every version of {@code service}. Called when the service
     * no longer has a current/baseline pair to compare (version retired from
     * the window, or only one version ever seen).
     */
    private void clearGaugesForService(String service) {
        ratios.entrySet().removeIf(e -> {
            if (!e.getKey().service().equals(service)) return false;
            var meter = meterRegistry.find(METRIC_NAME)
                .tag("service_name", e.getKey().service())
                .tag("version", e.getKey().version())
                .gauge();
            if (meter != null) meterRegistry.remove(meter);
            return true;
        });
    }

    private record GaugeKey(String service, String version) {}
}
