package com.unicorn.jvm.integration;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.localstack.LocalStackContainer;
import org.testcontainers.utility.DockerImageName;

// Testcontainers 2.0 initializer with fallback when Docker unavailable
public class TestInfrastructureInitializer implements BeforeAllCallback {

    private static final Logger logger = LoggerFactory.getLogger(TestInfrastructureInitializer.class);

    private static LocalStackContainer localstack;
    private static boolean dockerAvailable = false;

    @Override
    public void beforeAll(final ExtensionContext context) {
        logger.info("Checking Docker availability...");

        try {
            DockerClientFactory.instance().client();
            logger.info("Docker is available, initializing Testcontainers infrastructure...");
            initializeTestcontainers();
            dockerAvailable = true;
        } catch (Exception _) {
            // Java 22 unnamed variable (JEP 456)
            logger.warn("Docker is not available, using mock fallback for S3 tests");
            initializeMockFallback();
        }
    }

    private void initializeTestcontainers() {
        try {
            if (localstack == null) {
                localstack = new LocalStackContainer(DockerImageName.parse("localstack/localstack:3.0"))
                    .withServices("s3")
                    .withReuse(true);
                localstack.start();

                System.setProperty("aws.accessKeyId", "test");
                System.setProperty("aws.secretAccessKey", "test");
                System.setProperty("aws.region", "us-east-1");
                System.setProperty("jvm-ai-analyzer.s3.endpoint", localstack.getEndpoint().toString());

                createTestBucket();
            }

            logger.info("Successfully initialized Testcontainers infrastructure.");
            logger.info("LocalStack URL: {}", localstack.getEndpoint());
        } catch (Exception e) {
            logger.error("Failed to initialize Testcontainers: {}", e.getMessage());
            initializeMockFallback();
        }
    }

    private void createTestBucket() {
        try (var s3Client = software.amazon.awssdk.services.s3.S3Client.builder()
                .endpointOverride(localstack.getEndpoint())
                .region(software.amazon.awssdk.regions.Region.US_EAST_1)
                .credentialsProvider(software.amazon.awssdk.auth.credentials.StaticCredentialsProvider.create(
                    software.amazon.awssdk.auth.credentials.AwsBasicCredentials.create("test", "test")))
                .build()) {

            s3Client.createBucket(software.amazon.awssdk.services.s3.model.CreateBucketRequest.builder()
                .bucket("jvm-ai-analyzer-bucket")
                .build());

            logger.info("Created test bucket: jvm-ai-analyzer-bucket");
        } catch (Exception e) {
            logger.warn("Failed to create test bucket (may already exist): {}", e.getMessage());
        }
    }

    private void initializeMockFallback() {
        logger.info("Initializing mock fallback infrastructure...");

        System.setProperty("aws.accessKeyId", "test");
        System.setProperty("aws.secretAccessKey", "test");
        System.setProperty("aws.region", "us-east-1");

        logger.info("Successfully initialized mock fallback infrastructure.");
    }

    public static boolean isDockerAvailable() {
        return dockerAvailable;
    }

    public static LocalStackContainer getLocalstack() {
        return localstack;
    }
}
