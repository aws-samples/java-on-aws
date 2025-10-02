package com.unicorn.jvm;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(JvmAnalysisController.class)
class JvmAnalysisControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JvmAnalysisService jvmAnalysisService;

    @Test
    void handleWebhook_shouldProcessValidAlerts() throws Exception {
        String grafanaWebhook = """
            {
              "alerts": [
                {
                  "labels": {
                    "pod": "my-app-pod-123",
                    "instance": "10.0.1.100:8080"
                  }
                }
              ]
            }
            """;

        when(jvmAnalysisService.processValidatedAlerts(any(AlertWebhookRequest.class)))
                .thenReturn(Map.of("message", "Processed alerts", "count", 1));

        mockMvc.perform(post("/webhook")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(grafanaWebhook))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Processed alerts"))
                .andExpect(jsonPath("$.count").value(1));
    }

    @Test
    void handleWebhook_shouldReturnZeroForEmptyAlerts() throws Exception {
        String emptyWebhook = """
            {
              "alerts": []
            }
            """;

        mockMvc.perform(post("/webhook")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(emptyWebhook))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("No alerts to process"))
                .andExpect(jsonPath("$.count").value(0));
    }

    @Test
    void handleWebhook_shouldFilterInvalidAlerts() throws Exception {
        String webhookWithInvalidAlert = """
            {
              "alerts": [
                {
                  "labels": {
                    "alertname": "High CPU"
                  }
                }
              ]
            }
            """;

        when(jvmAnalysisService.processValidatedAlerts(any(AlertWebhookRequest.class)))
                .thenReturn(Map.of("message", "Processed alerts", "count", 0));

        mockMvc.perform(post("/webhook")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(webhookWithInvalidAlert))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Processed alerts"))
                .andExpect(jsonPath("$.count").value(0));
    }
}