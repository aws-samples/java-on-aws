package com.unicorn.store.integration;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SimpleInfrastructureInitializer implements BeforeAllCallback {
    private static final Logger logger = LoggerFactory.getLogger(SimpleInfrastructureInitializer.class);

    @Override
    public void beforeAll(final ExtensionContext context) {
        logger.info("Initializing simple test infrastructure without Docker...");
        
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
        
        // Activate test profile
        System.setProperty("spring.profiles.active", "test");
        
        logger.info("Successfully initialized simple test infrastructure.");
    }
}
