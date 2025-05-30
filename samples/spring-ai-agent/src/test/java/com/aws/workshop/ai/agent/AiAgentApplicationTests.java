package com.aws.workshop.ai.agent;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
        "spring.sql.init.mode=never",
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.liquibase.enabled=false"
})
class AiAgentApplicationTests {

    @Test
    void contextLoads() {
    }

}
