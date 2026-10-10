package com.example.perf.sensor.checklist;

import com.example.perf.sensor.SensorService;
import com.example.perf.sensor.collect.K8sCollector;
import com.example.perf.sensor.collect.PrometheusClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;

/**
 * The checklist score: waits until the service's pod is old enough to have steady-state facts,
 * collects them ({@code measure} plus {@code diagnoseBlocking} under load) and evaluates the
 * rules file over them. Same facts, same rules, same table, whoever asks (REST or MCP).
 */
@Service
public class ChecklistService {

    private static final Logger logger = LoggerFactory.getLogger(ChecklistService.class);
    private static final ObjectMapper MAPPER = JsonMapper.builder().build();
    public static final int DEFAULT_MIN_UPTIME_SECONDS = 120;

    /**
     * OK: scored, {@code items} and {@code markdown} set. SETTLING: the pod is younger than
     * minUptimeSeconds, {@code settleRemainingSeconds} > 0, nothing scored yet; call again.
     * {@code note}: why the call did not wait (no load flowing), or null.
     */
    public record ChecklistResult(String status, String service, Long score, Integer total,
                                  List<ChecklistEngine.Item> items, String markdown,
                                  Integer podUptimeSeconds, Integer settleRemainingSeconds,
                                  Double requestRatePerSec, String note) {}

    /** How far the current pod is from minUptimeSeconds, and whether waiting makes sense. */
    public record Settle(int uptimeSeconds, int remainingSeconds, boolean loadFlowing, String note) {}

    private final SensorService sensor;
    private final K8sCollector k8s;
    private final PrometheusClient prometheus;
    private final ChecklistEngine engine;

    public ChecklistService(SensorService sensor, K8sCollector k8s, PrometheusClient prometheus,
                            @Value("${CHECKLIST_RULES:}") String rulesFile) {
        this.sensor = sensor;
        this.k8s = k8s;
        this.prometheus = prometheus;
        try (InputStream in = rulesFile.isBlank()
                ? new ClassPathResource("checklist-rules.yaml").getInputStream()
                : Files.newInputStream(Path.of(rulesFile))) {
            this.engine = new ChecklistEngine(in);
        } catch (IOException e) {
            throw new UncheckedIOException("cannot read checklist rules " + rulesFile, e);
        }
        logger.info("checklist: {} rules from {}", engine.size(), rulesFile.isBlank() ? "classpath" : rulesFile);
    }

    public Settle settle(String service, int minUptimeSeconds) {
        var snap = k8s.collect(service, service);
        int uptime = snap.uptimeSeconds() == null ? 0 : snap.uptimeSeconds().intValue();
        int remaining = Math.max(0, minUptimeSeconds - uptime);
        if (remaining == 0) {
            return new Settle(uptime, 0, true, null);
        }
        Double rate = prometheus.requestRatePerSec(service, 1);
        if (rate == null || rate < engine.minRequestRate()) {
            return new Settle(uptime, 0, false, "pod is " + uptime + " s old but no load is flowing ("
                + (rate == null ? "no rate" : "%.2f rps".formatted(rate))
                + "): the load-dependent items are UNKNOWN; start the load and ask again");
        }
        return new Settle(uptime, remaining, true, null);
    }

    /**
     * Score the service. When its pod is younger than {@code minUptimeSeconds}, wait up to
     * {@code maxWaitSeconds} for it; if that is not enough, return SETTLING (nothing scored).
     */
    public ChecklistResult checklist(String service, int minUptimeSeconds, int maxWaitSeconds) {
        var s = settle(service, minUptimeSeconds);
        if (s.remainingSeconds() > 0 && maxWaitSeconds > 0) {
            sleep(Math.min(maxWaitSeconds, s.remainingSeconds()));
            s = settle(service, minUptimeSeconds);
        }
        if (s.remainingSeconds() > 0) {
            return new ChecklistResult("SETTLING", service, null, null, null, null,
                s.uptimeSeconds(), s.remainingSeconds(), null,
                "pod is " + s.uptimeSeconds() + " s old, scoring at " + minUptimeSeconds + " s");
        }
        return score(service, s.note());
    }

    /** Collect the facts now and evaluate the rules (no waiting). */
    public ChecklistResult score(String service, String note) {
        // The two collections are independent: run the 20 s of thread dumps next to measure.
        var blockingTask = new FutureTask<>(() -> sensor.diagnoseBlocking(service, 20, 500, engine.minRequestRate()));
        Thread.ofVirtual().name("checklist-dumps-" + service).start(blockingTask);
        var m = sensor.measure(service, 15, 0);
        SensorService.BlockingResult blocking;
        try {
            blocking = blockingTask.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("interrupted while sampling thread dumps", e);
        } catch (ExecutionException e) {
            throw new IllegalStateException("thread-dump sampling failed: " + e.getCause(), e.getCause());
        }
        var facts = new LinkedHashMap<String, Object>();
        facts.put("workload", plain(m.workload()));
        facts.put("runtime", plain(m.runtime()));
        facts.put("jfr", plain(m.jfr()));
        facts.put("profile", plain(m.profile()));
        facts.put("window", plain(m.window()));
        facts.put("threads", plain(blocking.threads()));
        facts.put("blocking", plain(new LinkedHashMap<>(Map.of("status", blocking.status()))));
        var items = engine.evaluate(facts);
        long score = ChecklistEngine.score(items);
        logger.info("checklist service={} score={}/{}", service, score, items.size());
        Double uptime = m.window() == null ? null : m.window().uptimeSeconds();
        return new ChecklistResult("OK", service, score, items.size(), items, ChecklistEngine.markdown(items),
            uptime == null ? null : uptime.intValue(), 0, m.window() == null ? null : m.window().requestRatePerSec(), note);
    }

    /** A record as plain maps and lists, nulls dropped (an absent fact), every number a double. */
    static Object plain(Object o) {
        if (o == null) {
            return null;
        }
        return normalize(MAPPER.convertValue(o, Object.class));
    }

    private static Object normalize(Object o) {
        if (o instanceof Map<?, ?> map) {
            var out = new LinkedHashMap<String, Object>();
            map.forEach((k, v) -> {
                Object n = normalize(v);
                if (n != null) {
                    out.put(String.valueOf(k), n);
                }
            });
            return out;
        }
        if (o instanceof List<?> list) {
            var out = new ArrayList<>();
            list.forEach(v -> out.add(normalize(v)));
            return out;
        }
        if (o instanceof Number n) {
            return n.doubleValue();
        }
        return o;
    }

    private static void sleep(int seconds) {
        try {
            Thread.sleep(seconds * 1000L);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
