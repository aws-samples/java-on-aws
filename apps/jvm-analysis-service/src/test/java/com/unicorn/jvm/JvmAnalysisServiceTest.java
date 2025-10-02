package com.unicorn.jvm;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.io.IOException;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class JvmAnalysisServiceTest {

    @Mock
    private FlameGraphConverter flameGraphConverter;

    @Mock
    private S3Connector s3Connector;

    @Mock
    private AIRecommendation aiRecommendation;

    @Mock
    private RestTemplate restTemplate;

    private JvmAnalysisService jvmAnalysisService;

    @BeforeEach
    void setUp() {
        jvmAnalysisService = new JvmAnalysisService(flameGraphConverter, s3Connector, aiRecommendation);
        ReflectionTestUtils.setField(jvmAnalysisService, "restTemplate", restTemplate);
        ReflectionTestUtils.setField(jvmAnalysisService, "threadDumpUrlTemplate", "http://{podIp}:8080/actuator/threaddump");
    }

    @Test
    void processValidatedAlerts_shouldProcessAllValidAlerts() throws IOException {
        AlertWebhookRequest request = createValidRequest();

        when(restTemplate.getForObject(anyString(), eq(String.class)))
                .thenReturn("thread dump data");
        when(s3Connector.getLatestProfilingData(anyString()))
                .thenReturn("profiling data");
        when(flameGraphConverter.convertToFlameGraph(anyString()))
                .thenReturn("<html>flamegraph</html>");
        when(aiRecommendation.analyzePerformance(anyString(), anyString()))
                .thenReturn("analysis result");

        Map<String, Object> result = jvmAnalysisService.processValidatedAlerts(request);

        assertEquals("Processed alerts", result.get("message"));
        assertEquals(2, result.get("count"));

        verify(s3Connector, times(2)).getLatestProfilingData(anyString());
        verify(flameGraphConverter, times(2)).convertToFlameGraph(anyString());
        verify(aiRecommendation, times(2)).analyzePerformance(anyString(), anyString());
        verify(s3Connector, times(2)).storeResults(anyString(), anyString(), anyString());
    }

    @Test
    void processValidatedAlerts_shouldHandleEmptyAlerts() {
        AlertWebhookRequest request = new AlertWebhookRequest();
        request.setAlerts(List.of());

        Map<String, Object> result = jvmAnalysisService.processValidatedAlerts(request);

        assertEquals("Processed alerts", result.get("message"));
        assertEquals(0, result.get("count"));

        verifyNoInteractions(flameGraphConverter, s3Connector, aiRecommendation, restTemplate);
    }

    @Test
    void processValidatedAlerts_shouldContinueOnException() throws IOException {
        AlertWebhookRequest request = createValidRequest();

        when(restTemplate.getForObject(anyString(), eq(String.class)))
                .thenReturn("Failed to get thread dump: Connection failed")
                .thenReturn("thread dump data");
        when(s3Connector.getLatestProfilingData(anyString()))
                .thenReturn("profiling data");
        when(flameGraphConverter.convertToFlameGraph(anyString()))
                .thenReturn("<html>flamegraph</html>");
        when(aiRecommendation.analyzePerformance(anyString(), anyString()))
                .thenReturn("analysis result");

        Map<String, Object> result = jvmAnalysisService.processValidatedAlerts(request);

        assertEquals("Processed alerts", result.get("message"));
        assertEquals(2, result.get("count")); // Both are processed, even with failures
    }

    private AlertWebhookRequest createValidRequest() {
        AlertWebhookRequest request = new AlertWebhookRequest();

        AlertWebhookRequest.Alert alert1 = new AlertWebhookRequest.Alert();
        AlertWebhookRequest.Labels labels1 = new AlertWebhookRequest.Labels();
        labels1.setPod("pod-1");
        labels1.setInstance("10.0.1.1:8080");
        alert1.setLabels(labels1);

        AlertWebhookRequest.Alert alert2 = new AlertWebhookRequest.Alert();
        AlertWebhookRequest.Labels labels2 = new AlertWebhookRequest.Labels();
        labels2.setPod("pod-2");
        labels2.setInstance("10.0.1.2:8080");
        alert2.setLabels(labels2);

        request.setAlerts(List.of(alert1, alert2));
        return request;
    }
}