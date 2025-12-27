package com.unicorn.jvm.integration;

import com.unicorn.jvm.S3Repository;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

// Integration tests for S3Repository using LocalStack
@ExtendWith(TestInfrastructureInitializer.class)
class S3RepositoryIntegrationTest {

    private static S3Client s3Client;
    private static S3Repository s3Repository;
    private static final String TEST_BUCKET = "jvm-ai-analyzer-test-bucket";

    @BeforeAll
    static void setUp() {
        assumeTrue(TestInfrastructureInitializer.isDockerAvailable(),
            "Docker not available, skipping S3 integration tests");

        var localstack = TestInfrastructureInitializer.getLocalstack();

        s3Client = S3Client.builder()
            .endpointOverride(localstack.getEndpoint())
            .region(Region.US_EAST_1)
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create("test", "test")))
            .build();

        try {
            s3Client.createBucket(CreateBucketRequest.builder()
                .bucket(TEST_BUCKET)
                .build());
        } catch (Exception _) {
            // Bucket may already exist
        }

        s3Repository = new S3Repository(s3Client);
        ReflectionTestUtils.setField(s3Repository, "bucket", TEST_BUCKET);
        ReflectionTestUtils.setField(s3Repository, "analysisPrefix", "analysis/");
        ReflectionTestUtils.setField(s3Repository, "profilingPrefix", "profiling/");
    }

    @Test
    void getLatestProfilingData_returnsDataWhenExists() {
        assumeTrue(TestInfrastructureInitializer.isDockerAvailable());

        var podName = "test-pod";
        var currentDate = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        var key = "profiling/" + podName + "/profile-" + currentDate + "/test.html";
        var content = "<html>Flamegraph data</html>";

        s3Client.putObject(
            PutObjectRequest.builder()
                .bucket(TEST_BUCKET)
                .key(key)
                .build(),
            RequestBody.fromString(content));

        var result = s3Repository.getLatestProfilingData(podName);

        assertEquals(content, result);
    }

    @Test
    void getLatestProfilingData_returnsFallbackWhenNotExists() {
        assumeTrue(TestInfrastructureInitializer.isDockerAvailable());

        var podName = "nonexistent-pod-" + System.currentTimeMillis();
        var result = s3Repository.getLatestProfilingData(podName);

        assertEquals("No profiling data available", result);
    }

    @Test
    void storeResults_storesThreeFiles() {
        assumeTrue(TestInfrastructureInitializer.isDockerAvailable());

        var podName = "store-test-pod";
        var threadDump = "Thread dump content";
        var profilingData = "<html>Profiling</html>";
        var analysis = "# Analysis Report";

        assertDoesNotThrow(() ->
            s3Repository.storeResults(podName, threadDump, profilingData, analysis));
    }
}
