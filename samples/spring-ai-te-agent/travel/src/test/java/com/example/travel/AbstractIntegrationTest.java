package com.example.travel;

import com.example.travel.config.TestcontainersConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

/**
 * Base class for integration tests that need a PostgreSQL database.
 * Automatically configures Testcontainers with PostgreSQL.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
public abstract class AbstractIntegrationTest {
}