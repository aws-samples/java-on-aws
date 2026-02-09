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
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

@Repository
public class S3Repository {

    private static final Logger logger = LoggerFactory.getLogger(S3Repository.class);
    private static final Pattern JFR_TIMESTAMP = Pattern.compile("profile-(\\d{8}-\\d{6})\\.jfr$");

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

    public record JfrFile(byte[] data, String key, String datetime) {}

    /**
     * Fetches the latest JFR file for a pod. Searches today and yesterday
     * to handle alerts firing around midnight.
     */
    public JfrFile getLatestJfr(String podName) {
        var now = LocalDateTime.now();
        var today = now.format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        var yesterday = now.minusDays(1).format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        var basePrefix = profilingPrefix + podName + "/profile-";

        // Search both days, latest file wins
        var latestFile = Stream.of(today, yesterday)
            .flatMap(date -> {
                var prefix = basePrefix + date;
                logger.info("Listing S3 objects with prefix: {}", prefix);
                return s3Client.listObjectsV2(ListObjectsV2Request.builder()
                    .bucket(bucket)
                    .prefix(prefix)
                    .build()).contents().stream();
            })
            .filter(obj -> obj.key().endsWith(".jfr"))
            .max(Comparator.comparing(S3Object::key));

        if (latestFile.isEmpty()) {
            logger.info("No JFR data found for pod: {}", podName);
            return null;
        }

        var key = latestFile.get().key();
        logger.info("Found JFR file: {} ({} bytes)", key, latestFile.get().size());

        byte[] data = fetchBytes(key);
        String datetime = extractDatetime(key);

        return new JfrFile(data, key, datetime);
    }

    /**
     * Stores analysis results with datetime from the JFR filename for correlation.
     */
    public void storeResults(String podName, String datetime, byte[] jfrData,
                             String profilingSummary, String threadDump,
                             String flamegraphHtml, String analysis) {
        try {
            putBytes(analysisPrefix + datetime + "_profiling_" + podName + ".jfr", jfrData);
            putObject(analysisPrefix + datetime + "_profiling_" + podName + ".md", profilingSummary);
            putObject(analysisPrefix + datetime + "_threaddump_" + podName + ".json", threadDump);
            putObject(analysisPrefix + datetime + "_flamegraph_" + podName + ".html", flamegraphHtml);
            putObject(analysisPrefix + datetime + "_analysis_" + podName + ".md", analysis);

            logger.info("Stored analysis results for pod {} with datetime {}", podName, datetime);
        } catch (Exception e) {
            logger.error("Failed to store results for pod {}: {}", podName, e.getMessage());
        }
    }

    private byte[] fetchBytes(String key) {
        return s3Client.getObjectAsBytes(GetObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .build()).asByteArray();
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

    private void putBytes(String key, byte[] data) {
        s3Client.putObject(
            PutObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .build(),
            RequestBody.fromBytes(data)
        );
    }

    /**
     * Extracts datetime from JFR filename pattern: profile-YYYYMMDD-HHmmss.jfr
     */
    static String extractDatetime(String key) {
        Matcher m = JFR_TIMESTAMP.matcher(key);
        if (m.find()) {
            return m.group(1);
        }
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));
    }
}
