package com.unicorn.jvm;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class JvmAnalysisController {

    private final JvmAnalysisService jvmAnalysisService;

    public JvmAnalysisController(JvmAnalysisService jvmAnalysisService) {
        this.jvmAnalysisService = jvmAnalysisService;
    }

    @PostMapping("/webhook")
    public Map<String, Object> handleWebhook(@RequestBody AlertWebhookRequest request) {
        if (request.getAlerts() == null || request.getAlerts().isEmpty()) {
            return Map.of("message", "No alerts to process", "count", 0);
        }
        
        AlertWebhookRequest validatedRequest = new AlertWebhookRequest();
        validatedRequest.setAlerts(request.getAlerts().stream()
                .filter(this::isValidAlert)
                .toList());
        
        return jvmAnalysisService.processValidatedAlerts(validatedRequest);
    }


    private boolean isValidAlert(AlertWebhookRequest.Alert alert) {
        if (alert == null || alert.getLabels() == null) return false;

        AlertWebhookRequest.Labels labels = alert.getLabels();
        String podName = labels.getPod();
        String podIp = labels.getPodIp();

        return podName != null && !podName.isEmpty() &&
                podIp != null && !podIp.isEmpty();
    }
}
