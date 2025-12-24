package com.unicorn.jvm;

import io.github.resilience4j.retry.annotation.Retry;
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
    private final AiAnalysisService aiAnalysisService;
    private final RestClient restClient;

    @Value("${jvm-ai-analyzer.thread-dump.url-template}")
    private String threadDumpUrlTemplate;

    public AnalyzerService(S3Repository s3Repository, AiAnalysisService aiAnalysisService, RestClient restClient) {
        this.s3Repository = s3Repository;
        this.aiAnalysisService = aiAnalysisService;
        this.restClient = restClient;
    }

    public AnalysisResult processAlerts(List<AlertWebhookRequest.Alert> alerts) {
        var successCount = new AtomicInteger(0);

        // Parallel processing with Virtual Threads (spring.threads.virtual.enabled=true)
        alerts.parallelStream().forEach(alert -> {
            try {
                processAlert(alert);
                successCount.incrementAndGet();
            } catch (Exception _) {
                // Java 22 unnamed variable (JEP 456) - exception logged in processAlert
            }
        });

        return new AnalysisResult("Processed alerts", successCount.get());
    }

    private void processAlert(AlertWebhookRequest.Alert alert) {
        long startTime = System.currentTimeMillis();
        var labels = alert.labels();
        var podName = labels.pod();
        var podIp = labels.podIp();

        logger.info("Starting analysis for pod: {} (IP: {})", podName, podIp);

        try {
            var threadDump = getThreadDump(podIp);
            var profilingData = s3Repository.getLatestProfilingData(podName);
            var analysis = aiAnalysisService.analyze(threadDump, profilingData);
            s3Repository.storeResults(podName, threadDump, profilingData, analysis);

            logger.info("Completed analysis for pod {} in {}ms",
                podName, System.currentTimeMillis() - startTime);
        } catch (Exception e) {
            logger.error("Failed to process alert for pod {}: {}", podName, e.getMessage());
            throw e;
        }
    }

    @Retry(name = "threadDump", fallbackMethod = "getThreadDumpFallback")
    String getThreadDump(String podIp) {
        var url = threadDumpUrlTemplate.replace("{podIp}", podIp);
        logger.info("Fetching thread dump from: {}", url);

        return restClient.get()
            .uri(url)
            .retrieve()
            .body(String.class);
    }

    @SuppressWarnings("unused") // Used by Resilience4j
    String getThreadDumpFallback(String podIp, Exception ex) {
        logger.warn("Failed to get thread dump for pod IP {} after retries: {}", podIp, ex.getMessage());
        return "Failed to retrieve thread dump: " + ex.getMessage();
    }
}
