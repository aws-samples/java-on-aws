package com.unicorn.store.integration;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.localstack.LocalStackContainer;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.DockerClientFactory;

public class TestcontainersInfrastructureInitializer implements BeforeAllCallback {
    private static final Logger logger = LoggerFactory.getLogger(TestcontainersInfrastructureInitializer.class);
    
    private static PostgreSQLContainer<?> postgres;
    private static LocalStackContainer localstack;
    private static boolean dockerAvailable = false;

    @Override
    public void beforeAll(final ExtensionContext context) {
        logger.info("Checking Docker availability...");
        
        try {
            DockerClientFactory.instance().client();
            dockerAvailable = true;
            logger.info("Docker is available, initializing Testcontainers infrastructure...");
            initializeTestcontainers();
        } catch (Exception e) {
            logger.warn("Docker is not available, falling back to H2 database: {}", e.getMessage());
            initializeH2Fallback();
        }
    }
    
    private void initializeTestcontainers() {
        try {
            // Start PostgreSQL container
            if (postgres == null) {
                postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:15-alpine"))
                        .withDatabaseName("unicornstore")
                        .withUsername("unicorn")
                        .withPassword("unicorn");
                postgres.start();
                
                // Set PostgreSQL properties
                System.setProperty("spring.datasource.url", postgres.getJdbcUrl());
                System.setProperty("spring.datasource.username", postgres.getUsername());
                System.setProperty("spring.datasource.password", postgres.getPassword());
                System.setProperty("spring.datasource.driver-class-name", "org.postgresql.Driver");
            }
            
            // Start LocalStack container
            if (localstack == null) {
                localstack = new LocalStackContainer(DockerImageName.parse("localstack/localstack:3.0"))
                        .withServices(LocalStackContainer.Service.S3, LocalStackContainer.Service.DYNAMODB);
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
        } catch (Exception e) {
            logger.error("Failed to initialize Testcontainers, falling back to H2: {}", e.getMessage());
            initializeH2Fallback();
        }
    }
    
    private void initializeH2Fallback() {
        logger.info("Initializing H2 fallback infrastructure...");
        
        // Set up in-memory H2 database properties
        System.setProperty("spring.datasource.url", "jdbc:h2:mem:testdb");
        System.setProperty("spring.datasource.username", "sa");
        System.setProperty("spring.datasource.password", "password");
        System.setProperty("spring.datasource.driver-class-name", "org.h2.Driver");
        
        // Set up mock AWS properties
        System.setProperty("aws.accessKeyId", "test");
        System.setProperty("aws.secretAccessKey", "test");
        System.setProperty("aws.region", "us-east-1");
        System.setProperty("aws.endpointUrl", "http://localhost:4566");
        
        logger.info("Successfully initialized H2 fallback infrastructure.");
    }
}
