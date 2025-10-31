package com.example.ai.agent;

import com.example.ai.agent.config.TestcontainersConfiguration;
import org.springframework.boot.SpringApplication;

/**
 * Test application class for AI Agent with Testcontainers support.
 *
 * This class is used by the spring-boot:test-run Maven goal to start
 * the application with Testcontainers-managed PostgreSQL database.
 *
 * Usage:
 * mvn spring-boot:test-run
 *
 * This will:
 * - Start a PostgreSQL container automatically
 * - Initialize the database with required schema
 * - Start the AI Agent application
 * - Clean up containers when stopped
 */
public class TestAiAgentApplication {

    public static void main(String[] args) {
        SpringApplication
                .from(AiAgentApplication::main)
                .with(TestcontainersConfiguration.class)
                .run(args);
    }
}