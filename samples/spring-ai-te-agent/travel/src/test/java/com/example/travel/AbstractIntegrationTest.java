package com.example.travel;

import com.example.travel.config.TestcontainersConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

/**
 * Abstract base class for integration tests in the Travel application.
 *
 * This class provides common configuration for all integration tests:
 * - Testcontainers configuration for PostgreSQL database
 * - Test profile activation
 * - Web environment setup for full integration testing
 * - Pre-loaded sample data for hotels, flights, and airports
 *
 * Usage:
 * Extend this class in your integration test classes:
 *
 * <pre>
 * {@code
 * @ExtendWith(MockitoExtension.class)
 * class MyServiceIntegrationTest extends AbstractIntegrationTest {
 *     // Your test methods here
 * }
 * }
 * </pre>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(TestcontainersConfiguration.class)
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "logging.level.org.testcontainers=WARN",
        "logging.level.com.github.dockerjava=WARN"
})
public abstract class AbstractIntegrationTest {
    // Base class for integration tests
    // Concrete test classes should extend this class
}