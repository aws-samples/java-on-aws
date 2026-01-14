package com.unicorn.store.integration;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.localstack.LocalStackContainer;
import org.testcontainers.utility.DockerImageName;

// Testcontainers 2.0 initializer with H2 fallback when Docker unavailable
// Uses container reuse (.withReuse(true)) for faster test execution
public class TestInfrastructureInitializer implements BeforeAllCallback {
    private static final Logger logger = LoggerFactory.getLogger(TestInfrastructureInitializer.class);

    private static PostgreSQLContainer postgres;
    private static LocalStackContainer localstack;

    @Override
    public void beforeAll(final ExtensionContext context) {
        logger.info("Checking Docker availability...");

        try {
            DockerClientFactory.instance().client();
            logger.info("Docker is available, initializing Testcontainers infrastructure...");
            initializeTestcontainers();
        } catch (Exception ignored) {
            logger.warn("Docker is not available, falling back to H2 database");
            initializeH2Fallback();
        }
    }

    @SuppressWarnings("resource")
    private void initializeTestcontainers() {
        try {
            // Start PostgreSQL container with reuse for faster tests
            if (postgres == null) {
                postgres = new PostgreSQLContainer(DockerImageName.parse("postgres:16-alpine"))
                        .withDatabaseName("unicornstore")
                        .withUsername("unicorn")
                        .withPassword("unicorn")
                        .withReuse(true);
                postgres.start();

                // Set PostgreSQL properties
                System.setProperty("spring.datasource.url", postgres.getJdbcUrl());
                System.setProperty("spring.datasource.username", postgres.getUsername());
                System.setProperty("spring.datasource.password", postgres.getPassword());
                System.setProperty("spring.datasource.driver-class-name", "org.postgresql.Driver");

                // Let Hibernate create schema (matches Aurora production behavior)
                System.setProperty("spring.sql.init.mode", "never");
                System.setProperty("spring.jpa.hibernate.ddl-auto", "create");
            }

            // Start LocalStack container with EventBridge (events service)
            // Testcontainers 2.0: services specified as strings
            if (localstack == null) {
                localstack = new LocalStackContainer(DockerImageName.parse("localstack/localstack:3.0"))
                        .withServices("events")
                        .withReuse(true);
                localstack.start();

                // Set AWS properties
                System.setProperty("aws.accessKeyId", "test");
                System.setProperty("aws.secretAccessKey", "test");
                System.setProperty("aws.region", "us-east-1");
                System.setProperty("aws.endpointUrl", localstack.getEndpoint().toString());
            }

            logger.info("Successfully initialized Testcontainers infrastructure.");
            logger.info("PostgreSQL URL: {}", postgres.getJdbcUrl());
            logger.info("LocalStack URL: {}", localstack.getEndpoint());
        } catch (Exception ignored) {
            logger.error("Failed to initialize Testcontainers, falling back to H2");
            initializeH2Fallback();
        }
    }

    private void initializeH2Fallback() {
        logger.info("Initializing H2 fallback infrastructure...");

        // Set up in-memory H2 database properties
        System.setProperty("spring.datasource.url", "jdbc:h2:mem:testdb;MODE=PostgreSQL");
        System.setProperty("spring.datasource.username", "sa");
        System.setProperty("spring.datasource.password", "password");
        System.setProperty("spring.datasource.driver-class-name", "org.h2.Driver");

        // Let Hibernate create schema
        System.setProperty("spring.sql.init.mode", "never");
        System.setProperty("spring.jpa.hibernate.ddl-auto", "create");

        // Set up mock AWS properties
        System.setProperty("aws.accessKeyId", "test");
        System.setProperty("aws.secretAccessKey", "test");
        System.setProperty("aws.region", "us-east-1");
        System.setProperty("aws.endpointUrl", "http://localhost:4566");

        logger.info("Successfully initialized H2 fallback infrastructure.");
    }
}
