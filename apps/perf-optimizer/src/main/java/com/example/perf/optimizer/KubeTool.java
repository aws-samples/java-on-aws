package com.example.perf.optimizer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.cert.CertificateFactory;
import java.time.Duration;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Minimal in-cluster Kubernetes client (no fabric8 / k8s-client dependency):
 * discovers the app Pod by its {@code app=<name>} label cluster-wide and reads
 * the Pod log to extract the MEASURED startup time — Spring's
 * "Started X in N seconds", or a CRaC "Restored X in N ms" after checkpoint
 * restore. Replaces canned startup numbers with live measurement.
 *
 * Auth uses the mounted ServiceAccount token + cluster CA. The perf-analyzer SA
 * is already authorized (ClusterRole: get/list pods + pods/log). Read-only, and
 * degrades gracefully (returns null) when not running in-cluster.
 */
@Component
public class KubeTool {

    private static final Logger logger = LoggerFactory.getLogger(KubeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String SA = "/var/run/secrets/kubernetes.io/serviceaccount";

    // Spring Boot: "Started StoreApplication in 12.91 seconds (process running for ...)"
    private static final Pattern STARTED = Pattern.compile("Started \\S+ in ([0-9.]+) seconds");
    // CRaC restore: "Restored StoreApplication in 234 ms" or "... in 0.234 seconds"
    private static final Pattern RESTORED = Pattern.compile("Restored \\S+ in ([0-9.]+) (ms|milliseconds|seconds)");

    private final HttpClient http;
    private final String apiBase = "https://kubernetes.default.svc";
    private final String token;
    private final boolean inCluster;

    public KubeTool() {
        HttpClient client = null;
        String tok = null;
        boolean ok = false;
        try {
            tok = Files.readString(Path.of(SA + "/token")).trim();
            var caCerts = CertificateFactory.getInstance("X.509")
                .generateCertificates(Files.newInputStream(Path.of(SA + "/ca.crt")));
            var ks = KeyStore.getInstance(KeyStore.getDefaultType());
            ks.load(null, null);
            int i = 0;
            for (var cert : caCerts) {
                ks.setCertificateEntry("ca" + (i++), cert);
            }
            var tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            tmf.init(ks);
            var ssl = SSLContext.getInstance("TLS");
            ssl.init(null, tmf.getTrustManagers(), null);
            client = HttpClient.newBuilder()
                .sslContext(ssl)
                .connectTimeout(Duration.ofSeconds(3))
                .build();
            ok = true;
        } catch (Exception e) {
            logger.warn("KubeTool: not in-cluster or SA unavailable ({}); startup measurement disabled",
                e.getMessage());
        }
        this.http = client;
        this.token = tok;
        this.inCluster = ok;
    }

    /** A located Pod: namespace, name, and the app (non-profiler) container. */
    public record PodRef(String namespace, String name, String container) {}

    /** Find a Running Pod labelled {@code app=<app>} cluster-wide (newest wins). null if none. */
    public PodRef findAppPod(String app) {
        if (!inCluster) {
            return null;
        }
        try {
            var uri = URI.create(apiBase + "/api/v1/pods?labelSelector="
                + URLEncoder.encode("app=" + app, StandardCharsets.UTF_8));
            var body = get(uri);
            if (body == null) {
                return null;
            }
            JsonNode best = null;
            for (var it : MAPPER.readTree(body).path("items")) {
                if (!"Running".equals(it.path("status").path("phase").asText())) {
                    continue;
                }
                if (best == null
                    || it.path("status").path("startTime").asText("")
                       .compareTo(best.path("status").path("startTime").asText("")) > 0) {
                    best = it;
                }
            }
            if (best == null) {
                return null;
            }
            var ns = best.path("metadata").path("namespace").asText();
            var name = best.path("metadata").path("name").asText();
            var containers = best.path("spec").path("containers");
            // Prefer the container named like the app; else the first non-profiler container.
            String container = app;
            boolean found = false;
            for (var c : containers) {
                if (app.equals(c.path("name").asText())) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                for (var c : containers) {
                    var cn = c.path("name").asText();
                    if (!"perf-profiler".equals(cn)) {
                        container = cn;
                        break;
                    }
                }
            }
            return new PodRef(ns, name, container);
        } catch (Exception e) {
            logger.warn("KubeTool.findAppPod({}) failed: {}", app, e.getMessage());
            return null;
        }
    }

    /** MEASURED startup line for the app, parsed from the Pod log. null if unavailable. */
    public String measuredStartup(PodRef pod) {
        if (!inCluster || pod == null) {
            return null;
        }
        try {
            var uri = URI.create(apiBase + "/api/v1/namespaces/" + pod.namespace()
                + "/pods/" + pod.name() + "/log?container=" + pod.container() + "&tailLines=2000");
            var log = get(uri);
            if (log == null) {
                return null;
            }
            Double restored = lastMatchSeconds(RESTORED.matcher(log), true);
            if (restored != null) {
                return "CRaC restore: **%.3f s** (pod %s/%s)".formatted(restored, pod.namespace(), pod.name());
            }
            Double started = lastMatchSeconds(STARTED.matcher(log), false);
            if (started != null) {
                return "Spring startup: **%.2f s** (pod %s/%s)".formatted(started, pod.namespace(), pod.name());
            }
            return null;
        } catch (Exception e) {
            logger.warn("KubeTool.measuredStartup failed: {}", e.getMessage());
            return null;
        }
    }

    /** Last regex match as seconds; hasUnit=true means group(2) may be ms → convert. */
    private static Double lastMatchSeconds(Matcher m, boolean hasUnit) {
        Double v = null;
        while (m.find()) {
            double x = Double.parseDouble(m.group(1));
            if (hasUnit && m.group(2).startsWith("m")) {
                x /= 1000.0;
            }
            v = x;
        }
        return v;
    }

    private String get(URI uri) throws Exception {
        var req = HttpRequest.newBuilder(uri)
            .header("Authorization", "Bearer " + token)
            .timeout(Duration.ofSeconds(5))
            .GET()
            .build();
        var resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() / 100 != 2) {
            logger.warn("K8s API {} -> HTTP {}", uri.getPath(), resp.statusCode());
            return null;
        }
        return resp.body();
    }
}
