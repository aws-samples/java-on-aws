package com.example.ai.agent.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.utility.DockerImageName;
import java.time.Duration;

/**
 * Testcontainers configuration for AI Agent application.
 *
 * This configuration provides a PostgreSQL container for testing and development
 * with automatic connection management using Spring Boot's @ServiceConnection.
 *
 * The container includes:
 * - PostgreSQL 16 with pgvector extension pre-installed
 * - Automatic database creation (ai_agent_db)
 * - Vector operations support for AI embeddings
 * - Automatic cleanup after tests
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    /**
     * Creates a PostgreSQL container with pgvector extension support.
     *
     * The @ServiceConnection annotation automatically configures Spring Boot
     * to use this container for database connections, eliminating the need
     * for manual connection string configuration.
     *
     * @return PostgreSQL container configured for AI Agent application
     */
    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        PostgreSQLContainer<?> container = new PostgreSQLContainer<>(DockerImageName.parse("pgvector/pgvector:pg16"))
                .withDatabaseName("ai_agent_db")
                .withUsername("postgres")
                .withPassword("postgres")
                .withStartupTimeout(Duration.ofMinutes(5))
                .withCreateContainerCmdModifier(cmd -> cmd.withName("ai-agent-postgres"));

        // Use the default wait strategy which waits for the database to accept connections
        container.waitingFor(Wait.defaultWaitStrategy());

        return container;
    }
}