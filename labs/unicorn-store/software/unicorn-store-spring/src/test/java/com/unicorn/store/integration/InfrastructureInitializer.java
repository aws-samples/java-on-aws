package com.unicorn.store.integration;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.containers.PostgreSQLContainer;

public class InfrastructureInitializer implements BeforeAllCallback {
    private static final Logger logger = LoggerFactory.getLogger(InfrastructureInitializer.class);
	// private static final DockerImageName LOCALSTACK_IMAGE = DockerImageName.parse("localstack/localstack:latest");
	
	// private static final LocalStackContainer localStackContainer = new LocalStackContainer(LOCALSTACK_IMAGE);

    @SuppressWarnings("resource")
	private static final PostgreSQLContainer<?> postgresContainer = new PostgreSQLContainer<>("postgres:16.4")
        .withDatabaseName("unicorns")
        .withUsername("postgres")
        .withPassword("postgres");

	@Override
	public void beforeAll(final ExtensionContext context) {
		logger.info("Initializaing the local infrastructure ...");
		
		postgresContainer.start();

		System.setProperty("spring.datasource.url", postgresContainer.getJdbcUrl());
        System.setProperty("spring.datasource.username", postgresContainer.getUsername());
        System.setProperty("spring.datasource.password", postgresContainer.getPassword());

		// localStackContainer.start();
		// addConfigurationProperties();
		
		logger.info("Successfully initialized the local infrastructure.");
	}

	// private void addConfigurationProperties() {
	// private void addConfigurationProperties() {
	// 	System.setProperty("com.behl.aws.access-key", localStackContainer.getAccessKey());
	// 	System.setProperty("com.behl.aws.secret-access-key", localStackContainer.getSecretKey());
	// 	System.setProperty("com.behl.aws.region", localStackContainer.getRegion());
	// 	System.setProperty("com.behl.aws.endpoint", localStackContainer.getEndpoint().toString());
	// }
}
