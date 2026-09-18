package com.example.perf.optimizer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * Query Prometheus (in-cluster) for the app container's MEASURED memory
 * footprint over a window: working-set floor (idle) and peak (the OOM-relevant
 * figure Kubernetes evicts on), plus the app's measured startup (Micrometer
 * {@code application.ready.time}). This replaces canned RSS numbers with live
 * measurement. Read-only; every accessor degrades gracefully (returns null) when
 * Prometheus is unavailable or has no series for the container.
 *
 * <p>Numeric accessors (MiB / seconds) feed the typed fact collectors; the
 * markdown {@code *Summary} helpers back the legacy {@code optimizeService} tool.
 */
@Component
public class PrometheusTool {

    private static final Logger logger = LoggerFactory.getLogger(PrometheusTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final double MIB = 1024.0 * 1024.0;

    private final RestClient restClient;
    private final String promUrl;

    public PrometheusTool(@Value("${PROMETHEUS_URL:http://prometheus-server.monitoring}") String promUrl) {
        this.promUrl = promUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.promUrl).build();
    }

    // --- typed accessors (MiB / seconds), null when no data ---------------------

    /** Working-set floor (idle) over the window, MiB. */
    public Double workingSetFloorMi(String namespace, String container, int mins) {
        return toMi(scalar("min_over_time(container_memory_working_set_bytes" + sel(namespace, container) + win(mins) + ")"));
    }

    /** Working-set peak over the window, MiB (sizing basis for limits). */
    public Double workingSetPeakMi(String namespace, String container, int mins) {
        return toMi(scalar("max_over_time(container_memory_working_set_bytes" + sel(namespace, container) + win(mins) + ")"));
    }

    /** Container RSS peak over the window, MiB. */
    public Double rssPeakMi(String namespace, String container, int mins) {
        return toMi(scalar("max_over_time(container_memory_rss" + sel(namespace, container) + win(mins) + ")"));
    }

    /** Measured startup in seconds (application.ready.time, falling back to started.time). */
    public Double startupSeconds(String app) {
        Double ready = scalar("application_ready_time_seconds{application=\"" + app + "\"}");
        return ready != null ? ready : scalar("application_started_time_seconds{application=\"" + app + "\"}");
    }

    /**
     * HTTP request rate (req/s) over the window from Micrometer
     * {@code http_server_requests_seconds_count}. Signals whether the window saw
     * real traffic (so a memory peak reflects load). null if the metric is absent.
     */
    public Double requestRatePerSec(String app, int mins) {
        return scalar("sum(rate(http_server_requests_seconds_count{application=\"" + app + "\"}[" + mins + "m]))");
    }

    // --- markdown summaries (legacy optimizeService) ----------------------------

    /** Working-set floor + peak (and RSS peak) as a markdown block; null if no data. */
    public String memorySummary(String namespace, String container, int mins) {
        var floor = workingSetFloorMi(namespace, container, mins);
        var peak = workingSetPeakMi(namespace, container, mins);
        var rssPeak = rssPeakMi(namespace, container, mins);
        if (floor == null && peak == null) {
            return null;
        }
        var sb = new StringBuilder();
        sb.append("- container working-set (OOM-relevant): floor **%s**, peak **%s** (last %dm)\n"
            .formatted(mib(floor), mib(peak), mins));
        if (rssPeak != null) {
            sb.append("- container RSS peak: **%s**\n".formatted(mib(rssPeak)));
        }
        return sb.toString();
    }

    /** Measured startup as a markdown line; null if the app is not scraped yet. */
    public String startupSummary(String app) {
        Double ready = scalar("application_ready_time_seconds{application=\"" + app + "\"}");
        Double started = scalar("application_started_time_seconds{application=\"" + app + "\"}");
        var primary = (ready != null) ? ready : started;
        if (primary == null) {
            return null;
        }
        var sb = new StringBuilder();
        sb.append("- startup (Micrometer application.ready.time): **%.2f s**".formatted(primary));
        if (ready != null && started != null && Math.abs(ready - started) > 0.01) {
            sb.append(" (started at %.2f s)".formatted(started));
        }
        sb.append("\n");
        return sb.toString();
    }

    // --- internals --------------------------------------------------------------

    private static String sel(String namespace, String container) {
        return "{namespace=\"" + namespace + "\",container=\"" + container + "\"}";
    }

    private static String win(int mins) {
        return "[" + mins + "m]";
    }

    /** Run an instant PromQL query and return the first sample's value, or null. */
    private Double scalar(String query) {
        try {
            var url = promUrl + "/api/v1/query?query=" + URLEncoder.encode(query, StandardCharsets.UTF_8);
            var body = restClient.get().uri(URI.create(url)).retrieve().body(String.class);
            var result = MAPPER.readTree(body).path("data").path("result");
            if (!result.isArray() || result.isEmpty()) {
                return null;
            }
            // instant vector sample: "value": [ <ts>, "<number>" ]
            var val = result.get(0).path("value");
            if (val.isArray() && val.size() == 2) {
                return Double.parseDouble(val.get(1).asText());
            }
            return null;
        } catch (Exception e) {
            logger.warn("Prometheus query failed [{}]: {}", query, e.getMessage());
            return null;
        }
    }

    private static Double toMi(Double bytes) {
        return bytes == null ? null : bytes / MIB;
    }

    private static String mib(Double mi) {
        return mi == null ? "n/a" : "%.0f MiB".formatted(mi);
    }
}
