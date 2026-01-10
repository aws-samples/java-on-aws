package com.example.ai.jvmanalyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class AnalyzerService {

    private static final Logger logger = LoggerFactory.getLogger(AnalyzerService.class);

    private final S3Repository s3Repository;
    private final AiService aiService;
    private final RestClient restClient;

    @Value("${analyzer.thread-dump.url-template}")
    private String threadDumpUrlTemplate;

    public AnalyzerService(S3Repository s3Repository, AiService aiService, RestClient restClient) {
        this.s3Repository = s3Repository;
        this.aiService = aiService;
        this.restClient = restClient;
    }

    public WebhookController.WebhookResponse processAlerts(List<WebhookController.Alert> alerts) {
        var successCount = new AtomicInteger(0);

        // Parallel processing with Virtual Threads
        alerts.parallelStream().forEach(alert -> {
            try {
                processAlert(alert);
                successCount.incrementAndGet();
            } catch (Exception _) {
                // Exception logged in processAlert
            }
        });

        return new WebhookController.WebhookResponse("Processed alerts", successCount.get());
    }

    private void processAlert(WebhookController.Alert alert) {
        long startTime = System.currentTimeMillis();
        var labels = alert.labels();
        var podName = labels.pod();
        var podIp = labels.podIp();

        logger.info("Starting analysis for pod: {} (IP: {})", podName, podIp);

        try {
            var threadDump = getThreadDump(podIp);
            var profilingData = s3Repository.getLatestProfilingData(podName);
            var analysis = aiService.analyze(threadDump, profilingData);
            s3Repository.storeResults(podName, threadDump, profilingData, analysis);

            logger.info("Completed analysis for pod {} in {}ms",
                podName, System.currentTimeMillis() - startTime);
        } catch (Exception e) {
            logger.error("Failed to process alert for pod {}: {}", podName, e.getMessage());
            throw e;
        }
    }

    String getThreadDump(String podIp) {
        var url = threadDumpUrlTemplate.replace("{podIp}", podIp);
        logger.info("Fetching thread dump from: {}", url);

        try {
            return restClient.get()
                .uri(url)
                .retrieve()
                .body(String.class);
        } catch (Exception e) {
            logger.warn("Failed to get thread dump for pod IP {}: {}", podIp, e.getMessage());
            return "Failed to retrieve thread dump: " + e.getMessage();
        }
    }
}
