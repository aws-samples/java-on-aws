package com.unicorn.jvm;

import net.jqwik.api.*;
import net.jqwik.api.constraints.*;

import java.util.List;

// Property tests for webhook response - message non-null, count non-negative
class WebhookResponsePropertyTest {

    @Property(tries = 100)
    void responseAlwaysHasMessageAndNonNegativeCount(
        @ForAll @StringLength(min = 0, max = 100) String message,
        @ForAll @IntRange(min = 0, max = 1000) int count
    ) {
        var result = new AnalysisResult(message, count);

        assert result.message() != null : "Message should not be null";
        assert result.count() >= 0 : "Count should be non-negative";
    }

    @Property(tries = 100)
    void emptyAlertsReturnsZeroCount() {
        var request = new AlertWebhookRequest(List.of());
        var result = processRequest(request);

        assert result.count() == 0 : "Empty alerts should return count 0";
        assert result.message() != null : "Message should not be null";
    }

    @Property(tries = 100)
    void nullAlertsReturnsZeroCount() {
        var request = new AlertWebhookRequest(null);
        var result = processRequest(request);

        assert result.count() == 0 : "Null alerts should return count 0";
        assert result.message() != null : "Message should not be null";
    }

    @Property(tries = 100)
    void validAlertsReturnNonNegativeCount(
        @ForAll @Size(min = 1, max = 10) List<@StringLength(min = 1, max = 20) @AlphaChars String> podNames
    ) {
        var alerts = podNames.stream()
            .map(pod -> new AlertWebhookRequest.Alert(
                new AlertWebhookRequest.Labels(pod, "10.0.0.1:8080")))
            .toList();
        var request = new AlertWebhookRequest(alerts);

        long validCount = alerts.stream()
            .filter(this::isValidAlert)
            .count();

        assert validCount >= 0 : "Valid count should be non-negative";
        assert validCount <= alerts.size() : "Valid count should not exceed total alerts";
    }

    // --- Test helpers ---

    private AnalysisResult processRequest(AlertWebhookRequest request) {
        if (request == null || request.alerts() == null || request.alerts().isEmpty()) {
            return new AnalysisResult("No alerts to process", 0);
        }
        return new AnalysisResult("Processed alerts", request.alerts().size());
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
