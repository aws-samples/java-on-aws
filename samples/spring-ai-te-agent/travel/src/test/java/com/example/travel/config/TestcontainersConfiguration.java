package com.example.travel.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.MountableFile;

@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"))
                .withDatabaseName("travel_db")
                .withUsername("postgres")
                .withPassword("postgres")
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
    }
}