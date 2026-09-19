package com.example.perf.sensor.collect;

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
 * Query Prometheus (in-cluster) for the app container's MEASURED memory footprint
 * over a window: working-set floor (idle) and peak (the OOM-relevant figure
 * Kubernetes evicts on), the app's measured startup (Micrometer
 * {@code application.ready.time}), and the request rate (signals whether the
 * window saw real load). Read-only; every accessor degrades to null when
 * Prometheus is unavailable or has no series for the container.
 */
@Component
public class PrometheusClient {

    private static final Logger logger = LoggerFactory.getLogger(PrometheusClient.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final double MIB = 1024.0 * 1024.0;

    private final RestClient restClient;
    private final String promUrl;

    public PrometheusClient(@Value("${PROMETHEUS_URL:http://prometheus-server.monitoring}") String promUrl) {
        this.promUrl = promUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.promUrl).build();
    }

    // Memory/startup series are PER POD. We aggregate across all pods of the workload
    // to a fleet worst-case (the sizing-relevant envelope), so the value is correct at
    // any replica count — not an arbitrary single pod. cAdvisor labels each series with
    // its own pod, so min_over_time/max_over_time is per-pod; the outer max()/min()
    // collapses across pods deterministically.

    /** Fleet working-set floor (idle) over the window, MiB: the highest per-pod idle. */
    public Double workingSetFloorMi(String namespace, String container, int mins) {
        return toMi(scalar("max(min_over_time(container_memory_working_set_bytes" + sel(namespace, container) + win(mins) + "))"));
    }

    /** Fleet working-set peak over the window, MiB: the worst per-pod peak (limits basis). */
    public Double workingSetPeakMi(String namespace, String container, int mins) {
        return toMi(scalar("max(max_over_time(container_memory_working_set_bytes" + sel(namespace, container) + win(mins) + "))"));
    }

    /** Fleet startup in seconds: the slowest pod (application.ready.time, then started.time). */
    public Double startupSeconds(String app) {
        Double ready = scalar("max(application_ready_time_seconds{application=\"" + app + "\"})");
        return ready != null ? ready : scalar("max(application_started_time_seconds{application=\"" + app + "\"})");
    }

    /**
     * HTTP request rate (req/s) over the window from Micrometer
     * {@code http_server_requests_seconds_count}. Signals whether the window saw
     * real traffic (so a memory peak reflects load). null if the metric is absent.
     */
    public Double requestRatePerSec(String app, int mins) {
        return scalar("sum(rate(http_server_requests_seconds_count{application=\"" + app + "\"}[" + mins + "m]))");
    }

    /** Per-pod working-set peak over the window, MiB (drill-down behind the fleet peak). */
    public java.util.Map<String, Double> perPodPeakMi(String namespace, String container, int mins) {
        var out = new java.util.LinkedHashMap<String, Double>();
        vectorByPod("max_over_time(container_memory_working_set_bytes" + sel(namespace, container) + win(mins) + ")")
            .forEach((pod, bytes) -> out.put(pod, bytes / MIB));
        return out;
    }

    /** Per-pod startup seconds (application.ready.time), keyed by pod. */
    public java.util.Map<String, Double> perPodStartup(String app) {
        return vectorByPod("application_ready_time_seconds{application=\"" + app + "\"}");
    }

    /** Run an instant query and return value per {@code pod} label (skips series with no pod). */
    private java.util.Map<String, Double> vectorByPod(String query) {
        var out = new java.util.LinkedHashMap<String, Double>();
        try {
            var url = promUrl + "/api/v1/query?query=" + URLEncoder.encode(query, StandardCharsets.UTF_8);
            var body = restClient.get().uri(URI.create(url)).retrieve().body(String.class);
            var result = MAPPER.readTree(body).path("data").path("result");
            if (result.isArray()) {
                for (var series : result) {
                    var pod = series.path("metric").path("pod").asText(null);
                    var val = series.path("value");
                    if (pod != null && val.isArray() && val.size() == 2) {
                        out.put(pod, Double.parseDouble(val.get(1).asText()));
                    }
                }
            }
        } catch (Exception e) {
            logger.warn("Prometheus vectorByPod failed [{}]: {}", query, e.getMessage());
        }
        return out;
    }

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
}
