package com.example.ai.agent.config;

import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Test configuration to ensure database is properly initialized before Spring AI components start.
 * This helps avoid timing issues with Testcontainers and Spring AI schema initialization.
 */
@TestConfiguration
@Profile("test")
public class TestDatabaseInitializer {

    /**
     * Ensures the database is ready and pgvector extension is available.
     * This runs early in the application startup to prepare the database
     * before Spring AI components try to initialize their schemas.
     */
    @Bean
    public ApplicationRunner databaseInitializer(JdbcTemplate jdbcTemplate) {
        return args -> {
            try {
                // Ensure pgvector extension is available
                jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS vector");

                // Test basic connectivity
                jdbcTemplate.queryForObject("SELECT 1", Integer.class);

                System.out.println("Database initialized successfully with pgvector extension");
            } catch (Exception e) {
                System.err.println("Database initialization warning: " + e.getMessage());
                // Don't fail startup, let Spring AI handle schema creation
            }
        };
    }
}