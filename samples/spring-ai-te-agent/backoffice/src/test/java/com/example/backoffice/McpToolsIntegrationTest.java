package com.example.backoffice;

import com.example.backoffice.currencies.CurrencyService;
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
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class McpToolsIntegrationTest {

    @LocalServerPort
    private int port;

    @MockitoBean
    private CurrencyService currencyService;

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
    void tearDown() throws Exception {
        if (client != null) {
            client.close();
        }
    }

    @Test
    void testMcpClientListTools() throws Exception {
        McpSchema.ListToolsResult result = client.listTools();

        assertThat(result).isNotNull();
        assertThat(result.tools()).isNotEmpty();
        assertThat(result.tools()).anyMatch(tool -> "getAvailability".equals(tool.name()));
        assertThat(result.tools()).anyMatch(tool -> "bookHotel".equals(tool.name()));
    }

    @Test
    void testGetAvailabilityToolCall() throws Exception {
        when(hotelService.getAvailability("Paris", "2024-12-01", "2024-12-03"))
                .thenReturn(Map.of("city", "Paris", "hotels", "Hotel A, Hotel B"));

        CallToolResult result = client.callTool(
                new CallToolRequest("getAvailability",
                        Map.of(
                                "city", "Paris",
                                "checkInDate", "2024-12-01",
                                "checkOutDate", "2024-12-03"
                        )));

        assertThat(result).isNotNull();
        assertThat(result.content()).isNotEmpty();

        ObjectMapper mapper = new ObjectMapper();
        String jsonContent = ((McpSchema.TextContent) result.content().get(0)).text();
        HotelAvailabilityResult availabilityResult = mapper.readValue(jsonContent, HotelAvailabilityResult.class);

        assertThat(availabilityResult.city()).isEqualTo("Paris");
        assertThat(availabilityResult.hotels()).isEqualTo("Hotel A, Hotel B");

        verify(hotelService).getAvailability("Paris", "2024-12-01", "2024-12-03");
    }

    @Test
    void testBookHotelTool() throws Exception {
        when(hotelService.bookHotel("Paris", "Hotel Ritz", "John Doe", "2024-12-01", "2024-12-03"))
                .thenReturn(Map.of("confirmation", "CONF123", "hotel", "Hotel Ritz"));

        CallToolResult result = client.callTool(
                new CallToolRequest("bookHotel",
                        Map.of(
                                "city", "Paris",
                                "hotelName", "Hotel Ritz",
                                "guestName", "John Doe",
                                "checkInDate", "2024-12-01",
                                "checkOutDate", "2024-12-03"
                        )));

        assertThat(result).isNotNull();
        assertThat(result.content()).isNotEmpty();

        ObjectMapper mapper = new ObjectMapper();
        String jsonContent = ((McpSchema.TextContent) result.content().get(0)).text();
        HotelBookingResult bookingResult = mapper.readValue(jsonContent, HotelBookingResult.class);

        assertThat(bookingResult.confirmation()).isEqualTo("CONF123");
        assertThat(bookingResult.hotel()).isEqualTo("Hotel Ritz");

        verify(hotelService).bookHotel("Paris", "Hotel Ritz", "John Doe", "2024-12-01", "2024-12-03");
    }
}