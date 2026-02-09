package com.example.ai.jvmanalyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@Service
public class AnalyzerService {

    private static final Logger logger = LoggerFactory.getLogger(AnalyzerService.class);

    private final S3Repository s3Repository;
    private final AiService aiService;
    private final RestClient restClient;
    private final ExecutorService asyncExecutor = Executors.newVirtualThreadPerTaskExecutor();

    @Value("${analyzer.thread-dump.url-template}")
    private String threadDumpUrlTemplate;

    @Value("${FLAMEGRAPH_INCLUDE:}")
    private String flamegraphInclude;

    private static final int MAX_RETRIES = 10;
    private static final long RETRY_DELAY_MS = 30_000;

    public AnalyzerService(S3Repository s3Repository, AiService aiService, RestClient restClient) {
        this.s3Repository = s3Repository;
        this.aiService = aiService;
        this.restClient = restClient;
    }

    public WebhookController.WebhookResponse processAlerts(List<WebhookController.Alert> alerts) {
        for (var alert : alerts) {
            asyncExecutor.submit(() -> processAlert(alert));
        }
        logger.info("Accepted {} alerts for async processing", alerts.size());
        return new WebhookController.WebhookResponse("Accepted alerts for processing", alerts.size());
    }

    private void processAlert(WebhookController.Alert alert) {
        long startTime = System.currentTimeMillis();
        var labels = alert.labels();
        var podName = labels.pod();
        var podIp = labels.podIp();

        logger.info("Starting analysis for pod: {} (IP: {})", podName, podIp);

        try {
            // 1. Fetch latest JFR from S3, retry until we get one with samples
            S3Repository.JfrFile jfrFile = null;
            JfrParser.JfrSummary summary = null;
            Path tempJfr = null;

            for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
                jfrFile = s3Repository.getLatestJfr(podName);
                if (jfrFile == null) {
                    logger.info("No JFR data for pod {}, attempt {}/{}, waiting {}s",
                        podName, attempt, MAX_RETRIES, RETRY_DELAY_MS / 1000);
                    Thread.sleep(RETRY_DELAY_MS);
                    continue;
                }

                tempJfr = Files.createTempFile("jfr-", ".jfr");
                Files.write(tempJfr, jfrFile.data());
                summary = JfrParser.parse(tempJfr);

                if (summary.totalSamples() > 0) {
                    logger.info("Found JFR with {} samples on attempt {}", summary.totalSamples(), attempt);
                    break;
                }

                logger.info("JFR has 0 samples for pod {}, attempt {}/{}, waiting {}s",
                    podName, attempt, MAX_RETRIES, RETRY_DELAY_MS / 1000);
                Files.deleteIfExists(tempJfr);
                tempJfr = null;
                summary = null;
                Thread.sleep(RETRY_DELAY_MS);
            }

            if (summary == null || summary.totalSamples() == 0) {
                logger.warn("No JFR with samples found for pod {} after {} attempts, skipping",
                    podName, MAX_RETRIES);
                if (tempJfr != null) Files.deleteIfExists(tempJfr);
                return;
            }

            // 2. Parse JFR → runtime metrics + collapsed stacks
            try {
                String runtimeMetrics = JfrParser.formatForModel(summary);

                // 3. Generate collapsed stacks for model (async-profiler attribution)
                String collapsedStacks;
                try {
                    collapsedStacks = FlamegraphGenerator.generateCollapsed(tempJfr);
                } catch (Exception e) {
                    logger.warn("Collapsed stacks generation failed: {}", e.getMessage());
                    collapsedStacks = null;
                }

                // 4. Generate flamegraph HTML for human viewing
                String flamegraphHtml;
                try {
                    flamegraphHtml = FlamegraphGenerator.generateHtml(tempJfr, flamegraphInclude);
                } catch (Exception e) {
                    logger.warn("Flamegraph generation failed: {}", e.getMessage());
                    flamegraphHtml = "Flamegraph generation failed: " + e.getMessage();
                }

                // 5. Combine runtime metrics + collapsed stacks for model
                String profilingSummary = runtimeMetrics;
                if (collapsedStacks != null && !collapsedStacks.isBlank()) {
                    profilingSummary += "## Collapsed Stacks (async-profiler)\n\n"
                        + "Each line: stack trace;...;method count\n\n```\n"
                        + collapsedStacks + "```\n";
                }

                // 6. Fetch thread dump (null if unavailable)
                var threadDump = getThreadDump(podIp);

                // 7. Send profiling summary + thread dump to model
                var analysis = aiService.analyze(threadDump, profilingSummary);

                // 8. Store all results with correlated datetime from JFR filename
                s3Repository.storeResults(podName, jfrFile.datetime(), jfrFile.data(),
                    profilingSummary, threadDump, flamegraphHtml, analysis);
            } finally {
                Files.deleteIfExists(tempJfr);
            }

            logger.info("Completed analysis for pod {} in {}ms (JFR: {}, datetime: {})",
                podName, System.currentTimeMillis() - startTime,
                jfrFile.key(), jfrFile.datetime());
        } catch (Exception e) {
            logger.error("Failed to process alert for pod {}: {}", podName, e.getMessage());
            throw new RuntimeException(e);
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
            return null;
        }
    }
}
