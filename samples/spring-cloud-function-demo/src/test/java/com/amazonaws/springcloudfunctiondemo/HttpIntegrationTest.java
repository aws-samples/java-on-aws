package com.amazonaws.springcloudfunctiondemo;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class HttpIntegrationTest {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;
    
    @Test
    public void testUppercaseFunction() {
        // Make the request
        var response = restTemplate.postForEntity(
                "http://localhost:" + port + "/upperCase",
                "Spring",
                String.class);
        // Verify response
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("SPRING", response.getBody());
    }
    
    @Test
    public void testHandleUnicornHelloFunction() {
        var fluffy = new com.amazonaws.springcloudfunctiondemo.Unicorn("Fluffy", 3);
        var headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        // Make the request for an existing unicorn
        var response = restTemplate.postForEntity(
                "http://localhost:" + port + "/helloUnicorn",
                fluffy,
                String.class);
        
        // Verify response
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("Hello Fluffy! You are 3 years old!", response.getBody());
    }
}
