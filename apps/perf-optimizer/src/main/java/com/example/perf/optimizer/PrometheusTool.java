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
 * figure Kubernetes evicts on). This replaces canned RSS numbers with live
 * measurement. Read-only; degrades gracefully (returns null) if Prometheus is
 * unavailable or has no series for the container.
 */
@Component
public class PrometheusTool {

    private static final Logger logger = LoggerFactory.getLogger(PrometheusTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RestClient restClient;
    private final String promUrl;

    public PrometheusTool(@Value("${PROMETHEUS_URL:http://prometheus-server.monitoring}") String promUrl) {
        this.promUrl = promUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.promUrl).build();
    }

    /**
     * Working-set floor + peak (and RSS peak) for the app container over the last
     * {@code mins} minutes, formatted as a markdown block. null if no data.
     */
    public String memorySummary(String namespace, String container, int mins) {
        try {
            var sel = "{namespace=\"" + namespace + "\",container=\"" + container + "\"}";
            var win = "[" + mins + "m]";
            Double floor = scalar("min_over_time(container_memory_working_set_bytes" + sel + win + ")");
            Double peak = scalar("max_over_time(container_memory_working_set_bytes" + sel + win + ")");
            Double rssPeak = scalar("max_over_time(container_memory_rss" + sel + win + ")");
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
        } catch (Exception e) {
            logger.warn("PrometheusTool.memorySummary failed ns={} container={}: {}",
                namespace, container, e.getMessage());
            return null;
        }
    }

    /** Run an instant PromQL query and return the first sample's value, or null. */
    private Double scalar(String query) {
        try {
            var url = promUrl + "/api/v1/query?query="
                + URLEncoder.encode(query, StandardCharsets.UTF_8);
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
            return null;
        }
    }

    private static String mib(Double bytes) {
        if (bytes == null) {
            return "n/a";
        }
        return "%.0f MiB".formatted(bytes / (1024.0 * 1024.0));
    }
}
