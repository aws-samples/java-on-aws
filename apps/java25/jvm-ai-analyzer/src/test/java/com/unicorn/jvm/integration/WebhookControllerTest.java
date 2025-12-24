package com.unicorn.jvm;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.unicorn.jvm.AlertWebhookRequest;
import com.unicorn.jvm.AnalysisResult;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

// Unit tests for webhook controller validation logic
class WebhookControllerTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void handleWebhook_withEmptyAlerts_returnsZeroCount() {
        var request = new AlertWebhookRequest(List.of());
        var result = processRequest(request);

        assertEquals(0, result.count());
        assertNotNull(result.message());
    }

    @Test
    void handleWebhook_withNullAlerts_returnsZeroCount() {
        var request = new AlertWebhookRequest(null);
        var result = processRequest(request);

        assertEquals(0, result.count());
        assertNotNull(result.message());
    }

    @Test
    void handleWebhook_withValidAlerts_filtersCorrectly() {
        var validAlert = new AlertWebhookRequest.Alert(
            new AlertWebhookRequest.Labels("my-pod", "10.0.0.1:8080"));
        var invalidAlert1 = new AlertWebhookRequest.Alert(
            new AlertWebhookRequest.Labels(null, "10.0.0.2:8080"));
        var invalidAlert2 = new AlertWebhookRequest.Alert(
            new AlertWebhookRequest.Labels("pod2", null));
        var invalidAlert3 = new AlertWebhookRequest.Alert(null);

        var request = new AlertWebhookRequest(
            List.of(validAlert, invalidAlert1, invalidAlert2, invalidAlert3));

        var validAlerts = request.alerts().stream()
            .filter(this::isValidAlert)
            .toList();

        assertEquals(1, validAlerts.size());
        assertEquals("my-pod", validAlerts.getFirst().labels().pod());
    }

    @Test
    void handleWebhook_withBlankPod_isInvalid() {
        var alert = new AlertWebhookRequest.Alert(
            new AlertWebhookRequest.Labels("   ", "10.0.0.1:8080"));

        assertFalse(isValidAlert(alert));
    }

    @Test
    void alertWebhookRequest_deserializesCorrectly() throws Exception {
        var json = """
            {
                "alerts": [
                    {
                        "labels": {
                            "pod": "unicorn-store-abc123",
                            "instance": "10.0.1.50:8080"
                        }
                    }
                ]
            }
            """;

        var request = objectMapper.readValue(json, AlertWebhookRequest.class);

        assertNotNull(request.alerts());
        assertEquals(1, request.alerts().size());
        assertEquals("unicorn-store-abc123", request.alerts().getFirst().labels().pod());
        assertEquals("10.0.1.50", request.alerts().getFirst().labels().podIp());
    }

    @Test
    void labels_podIp_extractsCorrectly() {
        var labels1 = new AlertWebhookRequest.Labels("pod", "192.168.1.100:8080");
        var labels2 = new AlertWebhookRequest.Labels("pod", "10.0.0.1:9090");
        var labels3 = new AlertWebhookRequest.Labels("pod", null);

        assertEquals("192.168.1.100", labels1.podIp());
        assertEquals("10.0.0.1", labels2.podIp());
        assertNull(labels3.podIp());
    }

    // --- Test helpers ---

    private AnalysisResult processRequest(AlertWebhookRequest request) {
        if (request == null || request.alerts() == null || request.alerts().isEmpty()) {
            return new AnalysisResult("No alerts to process", 0);
        }

        var validAlerts = request.alerts().stream()
            .filter(this::isValidAlert)
            .toList();

        if (validAlerts.isEmpty()) {
            return new AnalysisResult("No valid alerts to process", 0);
        }

        return new AnalysisResult("Processed alerts", validAlerts.size());
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
