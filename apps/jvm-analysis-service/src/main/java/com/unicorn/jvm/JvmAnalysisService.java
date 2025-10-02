package com.unicorn.jvm;

import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.time.LocalDateTime;
import java.util.Map;

@Service
public class JvmAnalysisService {

    private static final Logger logger = LoggerFactory.getLogger(JvmAnalysisService.class);

    private final RestTemplate restTemplate = new RestTemplate();
    private final FlameGraphConverter flameGraphConverter;
    private final S3Connector s3Connector;
    private final AIRecommendation aiRecommendation;

    @Value("${threaddump.url.template:http://{podIp}:8080/actuator/threaddump}")
    private String threadDumpUrlTemplate;

    public JvmAnalysisService(FlameGraphConverter flameGraphConverter, S3Connector s3Connector, AIRecommendation aiRecommendation) {
        this.flameGraphConverter = flameGraphConverter;
        this.s3Connector = s3Connector;
        this.aiRecommendation = aiRecommendation;
    }

    public Map<String, Object> processValidatedAlerts(AlertWebhookRequest request) {
        int count = 0;
        for (AlertWebhookRequest.Alert alert : request.getAlerts()) {
            try {
                processAlert(alert);
                count++;
            } catch (Exception e) {
                logger.error("Processing failed: {}", e.getMessage());
            }
        }
        return Map.of("message", "Processed alerts", "count", count);
    }

    private void processAlert(AlertWebhookRequest.Alert alert) {
        long startTime = System.currentTimeMillis();
        AlertWebhookRequest.Labels labels = alert.getLabels();
        String podName = labels.getPod();
        String podIp = labels.getPodIp();

        logger.info("Starting analysis for pod: {}", podName);

        String threadDump = getThreadDump(podIp);
        String profilingData = getProfilingDataWithFlameGraph(podName);
        String analysis;
        try {
            analysis = aiRecommendation.analyzePerformance(threadDump, profilingData);
        } catch (Exception e) {
            logger.warn("AI analysis failed for pod {}: {}", podName, e.getMessage());
            analysis = String.format("""
                # Thread Dump Analysis Report

                **Generated:** %s

                **Error:** AI analysis failed - %s

                ## Inputs
                - Thread dump size: %d characters
                - Profiling data size: %d characters

                Review manually or retry analysis.
                """,
                LocalDateTime.now().format(java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME),
                e.getMessage(),
                threadDump.length(),
                profilingData.length()
            );
        }
        s3Connector.storeResults(podName, threadDump, analysis);

        logger.info("Total processing time: {}ms", (System.currentTimeMillis() - startTime));
    }

    @Retry(name = "threadDump", fallbackMethod = "getThreadDumpFallback")
    private String getThreadDump(String podIp) {
        String url = threadDumpUrlTemplate.replace("{podIp}", podIp);
        return restTemplate.getForObject(url, String.class);
    }

    private String getThreadDumpFallback(String podIp, Exception ex) {
        logger.warn("Failed to get thread dump for pod IP {}: {}", podIp, ex.getMessage());
        return "Failed to get thread dump: " + ex.getMessage();
    }

    private String getProfilingDataWithFlameGraph(String taskPodId) {
        try {
            String content = s3Connector.getLatestProfilingData(taskPodId);
            if (content == null) {
                return "No profiling data available";
            }

            String timestamp = java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));
            s3Connector.storeProfilingData(taskPodId, content, timestamp);

            String flamegraph = flameGraphConverter.convertToFlameGraph(content);
            s3Connector.storeFlameGraph(taskPodId, flamegraph, timestamp);

            return String.format("Flamegraph (Top Performance Hotspots):\n%s", flamegraph);
        } catch (Exception e) {
            logger.error("Failed to process profiling data for taskPodId: {}", taskPodId, e);
            return "Failed to read profiling data: " + e.getMessage();
        }
    }
}
