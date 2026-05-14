package com.example.perf.analyzer;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Both analyzer entry points in one controller — matches the simplicity
 * of ai-jvm-analyzer's WebhookController.
 *
 *   POST /api/v1/analyze          developer on-demand
 *   POST /api/v1/grafana-webhook  Grafana alert trigger
 *
 * DTOs for both endpoints are inner records.
 */
@RestController
public class AnalyzeController {

    private static final Logger logger = LoggerFactory.getLogger(AnalyzeController.class);

    private final AnalysisService analysisService;

    private final io.kubernetes.client.openapi.apis.CoreV1Api k8s;

    public AnalyzeController(AnalysisService analysisService, io.kubernetes.client.openapi.apis.CoreV1Api k8s) {
        this.analysisService = analysisService;
        this.k8s = k8s;
    }

    @PostMapping("/api/v1/analyze")
    public ResponseEntity<AnalysisHandle> analyze(@Valid @RequestBody AnalyzeRequest body) {
        validateTarget(body);
        var request = new AnalysisService.AnalysisRequest(
            body.service(), body.platform(), body.pod(), body.task(),
            body.reason(), AnalysisService.TriggerSource.ON_DEMAND);
        logger.info("On-demand analysis requested: service={} platform={} target={}",
            request.service(), request.platform(), request.target());
        return ResponseEntity.accepted().body(analysisService.submit(request));
    }

    @PostMapping("/api/v1/grafana-webhook")
    public ResponseEntity<Void> onGrafanaAlert(@RequestBody GrafanaAlertPayload body) {
        if (body == null || body.alerts() == null) {
            return ResponseEntity.badRequest().build();
        }
        int accepted = 0;
        for (var alert : body.alerts()) {
            if (!"firing".equalsIgnoreCase(alert.status())) continue;
            var request = toRequest(alert.labels());
            if (request == null) {
                logger.warn("Skipping alert — missing required labels: {}", alert.labels());
                continue;
            }
            logger.info("Grafana webhook analysis: service={} platform={} target={}",
                request.service(), request.platform(), request.target());
            analysisService.submit(request);
            accepted++;
        }
        logger.info("Accepted {} firing alerts for analysis", accepted);
        return ResponseEntity.accepted().build();
    }

    private static void validateTarget(AnalyzeRequest r) {
        var hasPod = r.pod() != null && !r.pod().isBlank();
        var hasTask = r.task() != null && !r.task().isBlank();
        if (r.platform() == AnalysisService.Platform.EKS && !hasPod) {
            throw new IllegalArgumentException("pod is required for platform=eks");
        }
        if (r.platform() == AnalysisService.Platform.ECS_FARGATE && !hasTask) {
            throw new IllegalArgumentException("task is required for platform=ecs-fargate");
        }
    }

    /**
     * Derive the analysis request from Grafana alert labels. Whatever the
     * alert source, we expect either:
     *   - a {@code service_name} label that matches what the collector
     *     publishes (e.g. {@code unicorn-store-spring-eks}), with the
     *     {@code -eks}/{@code -ecs} suffix telling us the platform; or
     *   - a {@code service} label plus an explicit {@code platform} label.
     * For EKS we resolve a current pod by the {@code perf-profile/service}
     * label; for ECS the alert must carry an explicit {@code task} label.
     */
    private AnalysisService.AnalysisRequest toRequest(Map<String, String> labels) {
        if (labels == null) return null;
        var serviceLabel = labels.getOrDefault("service_name", labels.get("service"));
        if (serviceLabel == null || serviceLabel.isBlank()) return null;

        AnalysisService.Platform platform;
        String workload;
        if (serviceLabel.endsWith("-eks")) {
            platform = AnalysisService.Platform.EKS;
            workload = serviceLabel.substring(0, serviceLabel.length() - "-eks".length());
        } else if (serviceLabel.endsWith("-ecs")) {
            platform = AnalysisService.Platform.ECS_FARGATE;
            workload = serviceLabel.substring(0, serviceLabel.length() - "-ecs".length());
        } else {
            // Unsuffixed — honour explicit platform label if present.
            var platformLabel = labels.get("platform");
            if (platformLabel == null || platformLabel.isBlank()) return null;
            try {
                platform = AnalysisService.Platform.valueOf(
                    platformLabel.toUpperCase().replace('-', '_'));
            } catch (IllegalArgumentException _) {
                return null;
            }
            workload = serviceLabel;
        }

        String pod = null;
        String task = null;
        if (platform == AnalysisService.Platform.EKS) {
            pod = findPodForWorkload(workload);
            if (pod == null) {
                logger.warn("No pod found for workload={} with perf-profile/service label", workload);
                return null;
            }
        } else {
            task = labels.get("task");
            if (task == null || task.isBlank()) {
                logger.warn("No task in labels for workload={} on ECS", workload);
                return null;
            }
        }

        var reason = "Grafana alert: " + labels.getOrDefault("alertname", "unknown");
        return new AnalysisService.AnalysisRequest(
            workload, platform, pod, task, reason,
            AnalysisService.TriggerSource.GRAFANA_WEBHOOK);
    }

    /**
     * List all pods cluster-wide with the {@code perf-profile/service=<workload>}
     * label, return the name of the first Running one. Analyzer only needs any
     * single pod — the collector's view is one-pod-per-node anyway.
     */
    private String findPodForWorkload(String workload) {
        try {
            var resp = k8s.listPodForAllNamespaces()
                .labelSelector("perf-profile/service=" + workload)
                .execute();
            if (resp.getItems() == null) return null;
            for (var p : resp.getItems()) {
                var status = p.getStatus();
                if (status != null && "Running".equals(status.getPhase())) {
                    return p.getMetadata().getName();
                }
            }
            return null;
        } catch (Exception e) {
            logger.warn("findPodForWorkload({}) failed: {}", workload, e.getMessage());
            return null;
        }
    }

    // === DTOs ===

    public record AnalyzeRequest(
        @NotBlank String service,
        @NotNull AnalysisService.Platform platform,
        String pod,
        String task,
        String reason
    ) {}

    public record AnalysisHandle(String analysisId, String s3Prefix) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record GrafanaAlertPayload(String status, List<Alert> alerts) {
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Alert(
            String status,
            Map<String, String> labels,
            Map<String, String> annotations,
            String startsAt
        ) {}
    }
}
