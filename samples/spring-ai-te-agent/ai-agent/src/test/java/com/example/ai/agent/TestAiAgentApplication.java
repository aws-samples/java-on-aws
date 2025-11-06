package com.example.ai.agent;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.utility.DockerImageName;
import java.time.Duration;

public class TestAiAgentApplication {

    public static void main(String[] args) {
        SpringApplication
                .from(AiAgentApplication::main)
                .with(TestcontainersConfig.class)
                .run(args);
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class TestcontainersConfig {
        @Bean
        @ServiceConnection
        PostgreSQLContainer<?> postgresContainer() {
            PostgreSQLContainer<?> container = new PostgreSQLContainer<>(
                    DockerImageName.parse("pgvector/pgvector:pg16"))
                    .withDatabaseName("ai_agent_db")
                    .withUsername("postgres")
                    .withPassword("postgres")
                    .withStartupTimeout(Duration.ofMinutes(5))
                    .withCreateContainerCmdModifier(cmd -> cmd.withName("ai-agent-postgres"))
                    .withReuse(true);  // Reuse container between restarts

            container.waitingFor(Wait.defaultWaitStrategy());
            return container;
        }
    }
}
