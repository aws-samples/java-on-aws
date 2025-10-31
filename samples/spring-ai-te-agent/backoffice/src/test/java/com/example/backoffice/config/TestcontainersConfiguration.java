package com.example.backoffice.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"))
                .withDatabaseName("backoffice_db")
                .withUsername("postgres")
                .withPassword("postgres")
                .withCreateContainerCmdModifier(cmd -> cmd.withName("backoffice-postgres"))
                .withInitScript("init-backoffice-db.sql");
    }
}