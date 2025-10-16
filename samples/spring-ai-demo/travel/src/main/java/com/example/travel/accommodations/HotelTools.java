package com.example.travel.accommodations;

import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.List;

/**
 * This class provides tool-annotated methods for AI consumption
 * while delegating actual business logic to HotelService
 */
@Component
public class HotelTools {

    private final HotelService hotelService;

    public HotelTools(HotelService hotelService) {
        this.hotelService = hotelService;
    }

    @Bean
    public ToolCallbackProvider hotelToolsProvider(HotelTools hotelTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(hotelTools)
                .build();
    }

    @Tool(description = """
        Find hotels in a city for specific dates.
        Requires: city - Name of the city to search in,
                 checkInDate - Check-in date (YYYY-MM-DD),
                 numberOfNights - Number of nights to stay.
        Returns: List of available hotels sorted by price from lowest to highest.
        Errors: NOT_FOUND if no hotels found in the specified city.
        """)
    public List<Hotel> findHotelsByCity(String city, LocalDate checkInDate, Integer numberOfNights) {
        return hotelService.findHotelsByCity(city, checkInDate, numberOfNights);
    }

    @Tool(description = """
        Find hotel details by hotel name.
        Requires: hotelName - The name of the hotel.
        Returns: Complete hotel details including amenities, pricing, and availability.
        Errors: NOT_FOUND if hotel doesn't exist with the specified hotelName.
        """)
    public List<Hotel> findHotelsByName(String hotelName) {
        return hotelService.findHotelsByName(hotelName);
    }

    @Tool(description = """
        Get hotel details by ID.
        Requires: id - The unique identifier of the hotel.
        Returns: Complete hotel details including amenities, pricing, and availability.
        Errors: NOT_FOUND if hotel doesn't exist with the specified ID.
        """)
    public Hotel getHotel(String id) {
        return hotelService.getHotel(id);
    }
}
