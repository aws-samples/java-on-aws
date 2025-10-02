package com.unicorn.jvm;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.Optional;

@Component
public class S3Connector {

    private static final Logger logger = LoggerFactory.getLogger(S3Connector.class);
    private final S3Client s3Client;

    @Value("${aws.s3.bucket:default_bucket_name}")
    private String s3Bucket;

    @Value("${aws.s3.prefix.analysis:analysis/}")
    private String s3PrefixAnalysis;

    @Value("${aws.s3.prefix.profiling:profiling/}")
    private String s3PrefixProfiling;

    public S3Connector() {
        this.s3Client = S3Client.builder().build();
    }

    public String getLatestProfilingData(String taskPodId) {
        try {
            String currentDate = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
            String prefix = s3PrefixProfiling + taskPodId + "/" + currentDate;
            logger.info("Listing S3 objects with prefix: {}", prefix);

            ListObjectsV2Response listResponse = s3Client.listObjectsV2(
                    ListObjectsV2Request.builder()
                            .bucket(s3Bucket)
                            .prefix(prefix)
                            .build()
            );

            Optional<S3Object> latestFile = listResponse.contents().stream()
                    .filter(obj -> obj.key().endsWith(".txt"))
                    .max(Comparator.comparing(S3Object::lastModified));

            if (latestFile.isEmpty()) return null;

            String fullKey = latestFile.get().key();
            return s3Client.getObjectAsBytes(
                    GetObjectRequest.builder()
                            .bucket(s3Bucket)
                            .key(fullKey)
                            .build()
            ).asUtf8String();
        } catch (Exception e) {
            logger.error("Failed to read profiling data for taskPodId: {}", taskPodId, e);
            return null;
        }
    }

    public void storeProfilingData(String taskPodId, String content, String timestamp) {
        String profilingKey = s3PrefixAnalysis + timestamp + "_profiling_" + taskPodId + ".txt";
        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(s3Bucket)
                        .key(profilingKey)
                        .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(content)
        );
    }

    public void storeFlameGraph(String taskPodId, String flamegraph, String timestamp) {
        String flamegraphKey = s3PrefixAnalysis + timestamp + "_profiling_" + taskPodId + ".html";
        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(s3Bucket)
                        .key(flamegraphKey)
                        .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(flamegraph)
        );
    }

    public void storeResults(String taskPodId, String threadDump, String analysis) {
        String currentTimestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));

        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(s3Bucket)
                        .key(s3PrefixAnalysis + currentTimestamp + "_threaddump_" + taskPodId + ".json")
                        .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(threadDump)
        );
        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(s3Bucket)
                        .key(s3PrefixAnalysis + currentTimestamp + "_analysis_" + taskPodId + ".md")
                        .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(analysis)
        );
    }

    public String extractTimestampFromFileName(String fullKey) {
        String fileName = fullKey.substring(fullKey.lastIndexOf('/') + 1);
        return fileName.replace(".txt", "");
    }
}