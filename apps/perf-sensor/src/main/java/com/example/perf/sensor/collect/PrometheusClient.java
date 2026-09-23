package com.example.perf.sensor.collect;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Query Prometheus (in-cluster) for the app container's MEASURED footprint over a window:
 * working-set floor and peak (the figure Kubernetes evicts on), CPU usage p95, CFS
 * throttling, HTTP request rate and latency (Micrometer), and the startup gauges. Read-only;
 * every accessor degrades to null when Prometheus is unavailable or has no series.
 *
 * <p>cAdvisor series are PER POD. Fleet values aggregate across the workload's CURRENT pods
 * to a worst case (the sizing-relevant envelope), so they are correct at any replica count.
 * {@code podRegex} (from the K8s snapshot's Ready pods) keeps pods replaced by a rollout
 * inside the window out of the verdict; null means "all pods with that container name"
 * (fallback when the API is unavailable).
 */
@Component
public class PrometheusClient {

    private static final Logger logger = LoggerFactory.getLogger(PrometheusClient.class);
    private static final ObjectMapper MAPPER = JsonMapper.builder().build();
    private static final double MIB = 1024.0 * 1024.0;

    private final RestClient restClient;
    private final String promUrl;

    public PrometheusClient(@Value("${PROMETHEUS_URL:http://prometheus-server.monitoring}") String promUrl) {
        this.promUrl = promUrl.replaceAll("/$", "");
        this.restClient = RestClient.builder().baseUrl(this.promUrl).build();
    }

    /**
     * Fleet working-set floor over the window, MiB: the highest per-pod idle footprint. The
     * 5th percentile, not the minimum: a pod's first seconds after start have a near-zero
     * working set, and a minimum over a window that includes the start reads a few MiB —
     * which would make the floor safety factor and the peak-floor load signal meaningless.
     * The caller also clips {@code mins} to the pod's lifetime minus its first minute.
     */
    public Double workingSetFloorMi(String namespace, String container, String podRegex, int mins) {
        return toMi(scalar("max(quantile_over_time(0.05, container_memory_working_set_bytes"
            + sel(namespace, container, podRegex) + win(mins) + "))"));
    }

    /** Fleet working-set peak over the window, MiB: the worst per-pod peak (limits basis). */
    public Double workingSetPeakMi(String namespace, String container, String podRegex, int mins) {
        return toMi(scalar("max(max_over_time(container_memory_working_set_bytes"
            + sel(namespace, container, podRegex) + win(mins) + "))"));
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

    /**
     * p95 of the app container's CPU usage rate over the window, cores (worst pod). Steady-state
     * demand for the "CPU request reflects steady state" item; the 1m rate smooths scrape jitter,
     * the 95th percentile ignores the boot spike.
     */
    public Double cpuUsageP95Cores(String namespace, String container, String podRegex, int mins) {
        return scalar("max(quantile_over_time(0.95, rate(container_cpu_usage_seconds_total"
            + sel(namespace, container, podRegex) + "[1m])[" + mins + "m:30s]))");
    }

    /**
     * CFS throttled time as a share of CPU time used over the window, 0..1+ (worst pod);
     * null without cAdvisor or without CPU usage. Time-based on purpose: the classic
     * throttled-periods/periods ratio counts a 100 ms period as throttled even when a
     * bursty request used the whole quota in 5 ms, so it reads 20-30 % for a low-quota
     * JVM that lost almost no wall time. Throttled seconds over used seconds says how much
     * the workload actually waited relative to the work it did.
     */
    public Double cpuThrottledRatio(String namespace, String container, String podRegex, int seconds) {
        String w = "[" + seconds + "s]";
        // on(pod): the usage series carries an extra cpu="total" label the throttled series lacks.
        Double r = scalar("max(increase(container_cpu_cfs_throttled_seconds_total" + sel(namespace, container, podRegex) + w + ")"
            + " / on(pod) increase(container_cpu_usage_seconds_total" + sel(namespace, container, podRegex) + w + "))");
        return r == null || r.isNaN() || r.isInfinite() ? null : r;
    }

    /** Mean HTTP latency over the window, ms, non-actuator URIs (rate(sum)/rate(count)); null if no traffic. */
    public Double latencyMeanMs(String app, int mins) {
        Double s = scalar("sum(rate(http_server_requests_seconds_sum{application=\"" + app + "\",uri!~\"/actuator.*\"}" + win(mins) + "))"
            + " / sum(rate(http_server_requests_seconds_count{application=\"" + app + "\",uri!~\"/actuator.*\"}" + win(mins) + "))");
        return s == null || s.isNaN() ? null : s * 1000.0;
    }

    /** Max HTTP latency seen in the window, ms, non-actuator URIs (Micrometer decaying max). */
    public Double latencyMaxMs(String app, int mins) {
        Double s = scalar("max(max_over_time(http_server_requests_seconds_max{application=\"" + app + "\",uri!~\"/actuator.*\"}" + win(mins) + "))");
        return s == null ? null : s * 1000.0;
    }

    /** Per-pod working-set peak over the window, MiB, for the given pods (drill-down behind the fleet peak). */
    public Map<String, Double> perPodPeakMi(String namespace, String container, String podRegex, int mins) {
        var out = new LinkedHashMap<String, Double>();
        vectorByPod("max_over_time(container_memory_working_set_bytes" + sel(namespace, container, podRegex) + win(mins) + ")")
            .forEach((pod, bytes) -> out.put(pod, bytes / MIB));
        return out;
    }

    /** Per-pod startup seconds (Micrometer application.ready.time), keyed by pod. */
    public Map<String, Double> perPodStartup(String app) {
        return vectorByPod("application_ready_time_seconds{application=\"" + app + "\"}");
    }

    /**
     * Per-pod startup seconds as the sensor read them from each pod's log (Started/Restored),
     * keyed by pod. Preferred over application.ready.time: a CRaC checkpoint taken after startup
     * carries the BUILD-time ready metric into every restored pod, while the log names the restore.
     */
    public Map<String, Double> perPodStartupFromLog(String service) {
        return vectorByPod("perf_sensor_startup_seconds{service=\"" + service + "\"}");
    }

    /** Run an instant query and return value per {@code pod} label (skips series with no pod). */
    private Map<String, Double> vectorByPod(String query) {
        var out = new LinkedHashMap<String, Double>();
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

    private static String sel(String namespace, String container, String podRegex) {
        return "{namespace=\"" + namespace + "\",container=\"" + container + "\""
            + (podRegex == null ? "" : ",pod=~\"" + podRegex + "\"") + "}";
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
