package com.example.travel.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.MountableFile;
import java.time.Duration;

/**
 * Testcontainers configuration for Travel application.
 *
 * This configuration provides a PostgreSQL container for testing and development
 * with automatic connection management using Spring Boot's @ServiceConnection.
 *
 * The container includes:
 * - PostgreSQL 16 with Alpine Linux for smaller footprint
 * - Automatic database creation (travel_db)
 * - Pre-loaded sample data for hotels, flights, and airports
 * - Automatic cleanup after tests
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    /**
     * Creates a PostgreSQL container with pre-loaded travel data.
     *
     * The @ServiceConnection annotation automatically configures Spring Boot
     * to use this container for database connections, eliminating the need
     * for manual connection string configuration.
     *
     * @return PostgreSQL container configured for Travel application
     */
    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        PostgreSQLContainer<?> container = new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"))
                .withDatabaseName("travel_db")
                .withUsername("postgres")
                .withPassword("postgres")
                .withStartupTimeout(Duration.ofMinutes(5))
                .withCreateContainerCmdModifier(cmd -> cmd.withName("travel-postgres"))
                .withCopyFileToContainer(
                    MountableFile.forClasspathResource("init-travel-db.sql"),
                    "/docker-entrypoint-initdb.d/01-init-travel-db.sql"
                )
                .withCopyFileToContainer(
                    MountableFile.forClasspathResource("init-travel-hotels.sql"),
                    "/docker-entrypoint-initdb.d/02-init-travel-hotels.sql"
                )
                .withCopyFileToContainer(
                    MountableFile.forClasspathResource("init-travel-flights.sql"),
                    "/docker-entrypoint-initdb.d/03-init-travel-flights.sql"
                );

        // Use the default wait strategy which waits for the database to accept connections
        container.waitingFor(Wait.defaultWaitStrategy());

        return container;
    }
}