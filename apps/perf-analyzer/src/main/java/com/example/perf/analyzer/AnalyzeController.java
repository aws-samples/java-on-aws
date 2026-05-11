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

    public AnalyzeController(AnalysisService analysisService) {
        this.analysisService = analysisService;
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

    private static AnalysisService.AnalysisRequest toRequest(Map<String, String> labels) {
        if (labels == null) return null;
        var service = labels.getOrDefault("service_name", labels.get("service"));
        var platformLabel = labels.get("platform");
        if (service == null || service.isBlank() || platformLabel == null || platformLabel.isBlank()) {
            return null;
        }
        AnalysisService.Platform platform;
        try {
            platform = AnalysisService.Platform.valueOf(platformLabel.toUpperCase().replace('-', '_'));
        } catch (IllegalArgumentException _) {
            return null;
        }
        var pod = labels.get("pod");
        var task = labels.get("task");
        if ((platform == AnalysisService.Platform.EKS && (pod == null || pod.isBlank()))
            || (platform == AnalysisService.Platform.ECS_FARGATE && (task == null || task.isBlank()))) {
            return null;
        }
        var reason = "Grafana alert: " + labels.getOrDefault("alertname", "PerfProfileRegression");
        return new AnalysisService.AnalysisRequest(
            service, platform, pod, task, reason,
            AnalysisService.TriggerSource.GRAFANA_WEBHOOK);
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
