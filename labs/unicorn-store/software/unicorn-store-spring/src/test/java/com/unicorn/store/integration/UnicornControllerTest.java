package com.unicorn.store.integration;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.equalTo;

import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.MethodOrderer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import com.unicorn.store.model.Unicorn;
import org.testcontainers.containers.PostgreSQLContainer;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class UnicornControllerTest {

    @LocalServerPort
    private Integer port;

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:13.11")
        .withDatabaseName("unicorns")
        .withUsername("postgres")
        .withPassword("postgres");

    @BeforeEach
    void setUp() {
        RestAssured.baseURI = "http://localhost:" + port;
    }

    @Test
    @Order(1)
    void shouldGetNoUnicorns() {
        given()
            .contentType(ContentType.JSON)
        .when()
            .get("/unicorns")
        .then()
            .statusCode(200)
            .body(".", hasSize(0));
    }

    static String id1;

    @Test
    @Order(2)
    void shouldPostUnicorn1() {
        id1 =
            given()
                .contentType(ContentType.JSON)
                .body(new Unicorn("Unicorn1", "10", "Big", "standard"))
            .when()
                .post("/unicorns")
            .then()
                .statusCode(200)
                .body("id", notNullValue())
                .body("name", equalTo("Unicorn1"))
            .extract()
                .path("id");
         System.out.println(id1);
    }

    static String id2;

    @Test
    @Order(3)
    void shouldPostUnicorn2() {
        id2 =
            given()
                .contentType(ContentType.JSON)
                .body(new Unicorn("Unicorn2", "10", "Big", "standard"))
            .when()
                .post("/unicorns")
            .then()
                .statusCode(200)
                .body("id", notNullValue())
                .body("name", equalTo("Unicorn2"))
            .extract()
                .path("id");
         System.out.println(id2);
    }

    @Test
    @Order(4)
    void shouldPutUnicorn1() {
        given()
            .contentType(ContentType.JSON)
            .body(new Unicorn("Unicorn11", "10", "Big", "standard"))
        .when()
            .put("/unicorns/" + id1)
        .then()
            .statusCode(200)
            .body("id", equalTo(id1))
            .body("name", equalTo("Unicorn11"));
    }

    @Test
    @Order(5)
    void shouldGetTwoUnicorns() {
        given()
            .contentType(ContentType.JSON)
        .when()
            .get("/unicorns")
        .then()
            .statusCode(200)
            .body(".", hasSize(2));
    }

    @Test
    @Order(6)
    void shouldDeleteUnicorn2() {
        given()
            .contentType(ContentType.JSON)
        .when()
            .delete("/unicorns/" + id2)
        .then()
            .statusCode(200);
    }

    @Test
    @Order(7)
    void shouldNotGetUnicorn2() {
        given()
            .contentType(ContentType.JSON)
        .when()
            .get("/unicorns" + id2)
        .then()
            .statusCode(404);
    }

    @Test
    @Order(8)
    void shouldGetUnicorn1() {
        given()
            .contentType(ContentType.JSON)
        .when()
            .get("/unicorns/" + id1)
        .then()
            .statusCode(200)
            .body("id", equalTo(id1))
            .body("name", equalTo("Unicorn11"));
    }

    @Test
    @Order(9)
    void shouldGetOneUnicorn() {
        given()
            .contentType(ContentType.JSON)
        .when()
            .get("/unicorns")
        .then()
            .statusCode(200)
            .body(".", hasSize(1));
    }
}
