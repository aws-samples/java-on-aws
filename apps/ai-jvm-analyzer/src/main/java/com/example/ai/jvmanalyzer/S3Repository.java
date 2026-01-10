package com.example.ai.jvmanalyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;

@Repository
public class S3Repository {

    private static final Logger logger = LoggerFactory.getLogger(S3Repository.class);

    private final S3Client s3Client;

    @Value("${analyzer.s3.bucket}")
    private String bucket;

    @Value("${analyzer.s3.prefix.analysis:analysis/}")
    private String analysisPrefix;

    @Value("${analyzer.s3.prefix.profiling:profiling/}")
    private String profilingPrefix;

    public S3Repository(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    public String getLatestProfilingData(String podName) {
        try {
            var currentDate = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
            var prefix = profilingPrefix + podName + "/profile-" + currentDate;
            logger.info("Listing S3 objects with prefix: {}", prefix);

            var response = s3Client.listObjectsV2(ListObjectsV2Request.builder()
                .bucket(bucket)
                .prefix(prefix)
                .build());

            var latestFile = response.contents().stream()
                .filter(obj -> obj.key().endsWith(".html"))
                .max(Comparator.comparing(S3Object::lastModified));

            if (latestFile.isEmpty()) {
                logger.info("No profiling data found for pod: {}", podName);
                return "No profiling data available";
            }

            var key = latestFile.get().key();
            logger.info("Found profiling data: {}", key);
            return fetchObject(key);
        } catch (Exception e) {
            logger.error("Failed to get profiling data for pod {}: {}", podName, e.getMessage());
            return "Failed to read profiling data: " + e.getMessage();
        }
    }

    public void storeResults(String podName, String threadDump, String profilingData, String analysis) {
        var timestamp = currentTimestamp();

        try {
            putObject(analysisPrefix + timestamp + "_threaddump_" + podName + ".json", threadDump);
            putObject(analysisPrefix + timestamp + "_profiling_" + podName + ".html", profilingData);
            putObject(analysisPrefix + timestamp + "_analysis_" + podName + ".md", analysis);

            logger.info("Stored analysis results for pod {} with timestamp {}", podName, timestamp);
        } catch (Exception e) {
            logger.error("Failed to store results for pod {}: {}", podName, e.getMessage());
        }
    }

    private String fetchObject(String key) {
        var response = s3Client.getObjectAsBytes(GetObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .build());
        return response.asUtf8String();
    }

    private void putObject(String key, String content) {
        s3Client.putObject(
            PutObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .build(),
            RequestBody.fromString(content != null ? content : "")
        );
    }

    private String currentTimestamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));
    }
}
