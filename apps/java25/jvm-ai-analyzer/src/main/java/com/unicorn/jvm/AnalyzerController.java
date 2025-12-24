package com.unicorn.jvm;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Objects;

@RestController
public class AnalyzerController {

    private final AnalyzerService service;

    // Java 25 Flexible Constructor Bodies (JEP 513) - validation before field assignment
    public AnalyzerController(AnalyzerService service) {
        Objects.requireNonNull(service, "service must not be null");
        this.service = service;
    }

    @PostMapping("/webhook")
    public AnalysisResult handleWebhook(@RequestBody AlertWebhookRequest request) {
        if (request == null || request.alerts() == null || request.alerts().isEmpty()) {
            return new AnalysisResult("No alerts to process", 0);
        }

        var validAlerts = request.alerts().stream()
            .filter(this::isValidAlert)
            .toList();

        if (validAlerts.isEmpty()) {
            return new AnalysisResult("No valid alerts to process", 0);
        }

        return service.processAlerts(validAlerts);
    }

    private boolean isValidAlert(AlertWebhookRequest.Alert alert) {
        if (alert == null || alert.labels() == null) {
            return false;
        }
        var labels = alert.labels();
        return labels.pod() != null && !labels.pod().isBlank()
            && labels.podIp() != null && !labels.podIp().isBlank();
    }
}
