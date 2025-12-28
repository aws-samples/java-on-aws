package com.example.ai.jvmanalyzer;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Objects;

@RestController
public class WebhookController {

    private final AnalyzerService service;

    public WebhookController(AnalyzerService service) {
        Objects.requireNonNull(service, "service must not be null");
        this.service = service;
    }

    @PostMapping("/webhook")
    public WebhookResponse handleWebhook(@RequestBody WebhookRequest request) {
        if (request == null || request.alerts() == null || request.alerts().isEmpty()) {
            return new WebhookResponse("No alerts to process", 0);
        }

        var validAlerts = request.alerts().stream()
            .filter(this::isValidAlert)
            .toList();

        if (validAlerts.isEmpty()) {
            return new WebhookResponse("No valid alerts to process", 0);
        }

        return service.processAlerts(validAlerts);
    }

    private boolean isValidAlert(Alert alert) {
        if (alert == null || alert.labels() == null) {
            return false;
        }
        var labels = alert.labels();
        return labels.pod() != null && !labels.pod().isBlank()
            && labels.podIp() != null && !labels.podIp().isBlank();
    }

    // === DTOs ===

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record WebhookRequest(
        @JsonProperty("alerts") List<Alert> alerts
    ) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Alert(
        @JsonProperty("labels") Labels labels
    ) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Labels(
        @JsonProperty("pod") String pod,
        @JsonProperty("instance") String instance
    ) {
        public String podIp() {
            return instance != null ? instance.split(":")[0] : null;
        }
    }

    public record WebhookResponse(
        String message,
        int count
    ) {}
}
