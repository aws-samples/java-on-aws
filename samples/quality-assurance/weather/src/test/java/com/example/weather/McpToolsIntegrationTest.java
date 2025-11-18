package com.example.weather;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.spec.McpSchema;
import io.modelcontextprotocol.spec.McpSchema.CallToolRequest;
import io.modelcontextprotocol.spec.McpSchema.CallToolResult;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class McpToolsIntegrationTest {

    @LocalServerPort
    private int port;

    @MockitoBean
    private WeatherService weatherService;

    private McpSyncClient client;

    @BeforeEach
    void setUp() {
        var client = McpClient.sync(
                        HttpClientStreamableHttpTransport
                                .builder("http://localhost:" + port)
                                .build())
                .build();

        client.initialize();
        this.client = client;
    }

    @AfterEach
    void tearDown() {
        if (client != null) {
            client.close();
        }
    }

    @Test
    void testMcpClientListTools() {
        McpSchema.ListToolsResult result = client.listTools();

        assertThat(result).isNotNull();
        assertThat(result.tools()).isNotEmpty();
        assertThat(result.tools()).anyMatch(tool -> "getWeatherForecast".equals(tool.name()));
    }

    @Test
    void testGetAvailabilityToolCall() throws Exception {
        when(weatherService.getWeather(anyString(), anyString()))
                .thenReturn("test weather forecast");

        CallToolResult result = client.callTool(
                new CallToolRequest("getWeatherForecast ",
                        Map.of(
                                "city", "Berlin",
                                "date", "2025-12-01"
                        )));

        assertThat(result).isNotNull();
        assertThat(result.content()).isNotEmpty();

        ObjectMapper mapper = new ObjectMapper();
        String resultString = ((McpSchema.TextContent) result.content().getFirst()).text();

        assertThat(resultString).isEqualTo("test weather forecast");

        verify(weatherService).getWeather("Berlin", "2025-12-01");
    }
}