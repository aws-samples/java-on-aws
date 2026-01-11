package com.unicorn.store.integration;

import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.localstack.LocalStackContainer;
import org.testcontainers.utility.DockerImageName;

public class InfrastructureInitializer implements BeforeAllCallback {
    private static final Logger logger = LoggerFactory.getLogger(InfrastructureInitializer.class);
	
	private static final DockerImageName LOCALSTACK_IMAGE = DockerImageName.parse("localstack/localstack:latest");
	@SuppressWarnings("resource")
	private static final LocalStackContainer localStackContainer = new LocalStackContainer(LOCALSTACK_IMAGE)
		.withServices(LocalStackContainer.EnabledService.named("events"));

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

		localStackContainer.start();
		// https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html
		System.setProperty("aws.accessKeyId", localStackContainer.getAccessKey());
		System.setProperty("aws.secretAccessKey", localStackContainer.getSecretKey());
		System.setProperty("aws.region", localStackContainer.getRegion());
		// https://docs.aws.amazon.com/sdkref/latest/guide/feature-ss-endpoints.html
		System.setProperty("aws.endpointUrl", localStackContainer.getEndpoint().toString());
		
		logger.info("Successfully initialized the local infrastructure.");
	}	
}
