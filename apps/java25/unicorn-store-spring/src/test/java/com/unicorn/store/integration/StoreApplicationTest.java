package com.unicorn.store.integration;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestInfrastructure
class StoreApplicationTest {

    @Test
    void contextLoads() {
        // This test verifies that the Spring application context loads successfully
    }
}