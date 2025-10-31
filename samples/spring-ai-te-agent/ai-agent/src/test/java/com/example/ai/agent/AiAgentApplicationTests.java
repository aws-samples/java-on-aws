package com.example.ai.agent;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Basic test for AI Agent Application.
 *
 * This test verifies that the Spring application can start successfully.
 * Uses a simpler approach without full Testcontainers integration for now.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@ActiveProfiles("test")
class AiAgentApplicationTests {

	@Test
	void contextLoads() {
		// Test that the application context loads successfully
		// This is a basic smoke test
	}
}