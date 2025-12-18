package com.unicorn.store.integration;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
@InitializeTestcontainersInfrastructure
class StoreApplicationTest {

    @Test
    void contextLoads() {
        // This test verifies that the Spring application context loads successfully
    }
}