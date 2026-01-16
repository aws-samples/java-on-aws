package com.unicorn.store.integration;

import com.unicorn.store.model.Unicorn;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.MediaType;
import org.springframework.test.web.reactive.server.WebTestClient;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestInfrastructure
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class WebControllerTest {

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
    void shouldLoadWebUIPage() {
        webTestClient.get()
            .uri("/webui")
            .exchange()
            .expectStatus().isOk()
            .expectHeader().contentTypeCompatibleWith(MediaType.TEXT_HTML);
    }

    @Test
    @Order(2)
    void shouldLoadIndexPage() {
        webTestClient.get()
            .uri("/")
            .exchange()
            .expectStatus().isOk()
            .expectHeader().contentTypeCompatibleWith(MediaType.TEXT_HTML);
    }

    static String createdId;

    @Test
    @Order(3)
    void shouldCreateUnicornViaRestAPI() {
        Unicorn unicorn = new Unicorn("WebTestUnicorn", "5", "Medium", "Rainbow", "Purple");
        
        createdId = webTestClient.post()
            .uri("/unicorns")
            .bodyValue(unicorn)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Unicorn.class)
            .returnResult()
            .getResponseBody()
            .getId();

        assertThat(createdId).isNotNull();
    }

    @Test
    @Order(4)
    void shouldLoadListFragment() {
        webTestClient.get()
            .uri("/webui/list")
            .exchange()
            .expectStatus().isOk()
            .expectBody(String.class)
            .value(html -> {
                assertThat(html).contains("WebTestUnicorn");
                assertThat(html).contains("Purple");
            });
    }

    @Test
    @Order(5)
    void shouldLoadEditForm() {
        webTestClient.get()
            .uri("/webui/edit/" + createdId)
            .exchange()
            .expectStatus().isOk()
            .expectBody(String.class)
            .value(html -> {
                assertThat(html).contains("WebTestUnicorn");
                assertThat(html).contains("form");
            });
    }

    @Test
    @Order(6)
    void shouldDeleteViaWebUI() {
        webTestClient.delete()
            .uri("/webui/delete/" + createdId)
            .exchange()
            .expectStatus().isOk();

        webTestClient.get()
            .uri("/unicorns/" + createdId)
            .exchange()
            .expectStatus().isNotFound();
    }
}
