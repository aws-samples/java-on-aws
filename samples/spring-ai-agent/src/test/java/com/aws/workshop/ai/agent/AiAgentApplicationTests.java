package com.aws.workshop.ai.agent;

import org.hamcrest.Matchers;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class AiAgentApplicationTests {

    @SuppressWarnings({"unused", "resource"})
    @Container
    private static final PostgreSQLContainer<?> postgresContainer = new PostgreSQLContainer<>(
            DockerImageName.parse("pgvector/pgvector:pg16")
                    .asCompatibleSubstituteFor("postgres"))
            .withDatabaseName("ai-agent-db")
            .withUsername("chatuser")
            .withPassword("chatpass");

    @DynamicPropertySource
    static void overrideProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgresContainer::getJdbcUrl);
        registry.add("spring.datasource.username", postgresContainer::getUsername);
        registry.add("spring.datasource.password", postgresContainer::getPassword);
    }
    @Test
    void contextLoads() {
    }

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void testRagPgVectorEndpoint() {
        webTestClient.post().uri("/rag-pgvector/load")
                .bodyValue("Weather in Munich today is 20 degrees and sunny")
                .exchange()
                .expectStatus().isOk();

        webTestClient.post().uri("/rag-pgvector/chat")
                .bodyValue("What is the weather in Munich?")
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(Matchers.containsString("20 degrees"))
                .value(Matchers.containsString("sunny"));
    }

    @Test
    void testExternalizedMemoryEndpoint() {
        webTestClient.post().uri("/ext-memory/chat")
                .bodyValue("My name is Andrei")
                .exchange()
                .expectStatus().isOk();

        webTestClient.post().uri("/ext-memory/chat")
                .bodyValue("What is my name?")
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(Matchers.containsString("Andrei"));
    }

}
