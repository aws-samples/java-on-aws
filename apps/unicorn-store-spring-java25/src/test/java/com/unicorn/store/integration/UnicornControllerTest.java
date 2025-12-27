package com.unicorn.store.integration;

import com.unicorn.store.model.Unicorn;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.web.reactive.server.WebTestClient;

import static org.assertj.core.api.Assertions.assertThat;

// Integration tests for UnicornController using WebTestClient
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestInfrastructure
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class UnicornControllerTest {

    @LocalServerPort
    private int port;

    private WebTestClient webTestClient;

    @BeforeEach
    void setUp() {
        webTestClient = WebTestClient.bindToServer()
            .baseUrl("http://localhost:" + port)
            .build();
    }

    @Test
    @Order(1)
    void shouldGetNoUnicorns() {
        webTestClient.get()
            .uri("/unicorns")
            .exchange()
            .expectStatus().isNoContent();
    }

    static String id1;

    @Test
    @Order(2)
    void shouldPostUnicorn1() {
        Unicorn unicorn = new Unicorn("Unicorn1", "10", "Big", "standard");

        id1 = webTestClient.post()
            .uri("/unicorns")
            .bodyValue(unicorn)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Unicorn.class)
            .returnResult()
            .getResponseBody()
            .getId();

        assertThat(id1).isNotNull().isNotBlank();
    }

    static String id2;

    @Test
    @Order(3)
    void shouldPostUnicorn2() {
        Unicorn unicorn = new Unicorn("Unicorn2", "10", "Big", "standard");

        id2 = webTestClient.post()
            .uri("/unicorns")
            .bodyValue(unicorn)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Unicorn.class)
            .returnResult()
            .getResponseBody()
            .getId();

        assertThat(id2).isNotNull().isNotBlank();
    }

    @Test
    @Order(4)
    void shouldPutUnicorn1() {
        Unicorn unicorn = new Unicorn("Unicorn11", "10", "Big", "standard");

        webTestClient.put()
            .uri("/unicorns/" + id1)
            .bodyValue(unicorn)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Unicorn.class)
            .value(u -> {
                assertThat(u.getId()).isEqualTo(id1);
                assertThat(u.getName()).isEqualTo("Unicorn11");
            });
    }

    @Test
    @Order(5)
    void shouldGetTwoUnicorns() {
        webTestClient.get()
            .uri("/unicorns")
            .exchange()
            .expectStatus().isOk()
            .expectBodyList(Unicorn.class)
            .hasSize(2);
    }

    @Test
    @Order(6)
    void shouldDeleteUnicorn2() {
        webTestClient.delete()
            .uri("/unicorns/" + id2)
            .exchange()
            .expectStatus().isOk();
    }

    @Test
    @Order(7)
    void shouldNotGetUnicorn2() {
        webTestClient.get()
            .uri("/unicorns/" + id2)
            .exchange()
            .expectStatus().isNotFound();
    }

    @Test
    @Order(8)
    void shouldGetUnicorn1() {
        webTestClient.get()
            .uri("/unicorns/" + id1)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Unicorn.class)
            .value(u -> {
                assertThat(u.getId()).isEqualTo(id1);
                assertThat(u.getName()).isEqualTo("Unicorn11");
            });
    }

    @Test
    @Order(9)
    void shouldGetOneUnicorn() {
        webTestClient.get()
            .uri("/unicorns")
            .exchange()
            .expectStatus().isOk()
            .expectBodyList(Unicorn.class)
            .hasSize(1);
    }
}
