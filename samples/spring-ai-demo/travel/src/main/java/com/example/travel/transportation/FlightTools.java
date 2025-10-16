package com.example.travel.transportation;

import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * This class provides tool-annotated methods for AI consumption
 * while delegating actual business logic to FlightService
 */
@Component
public class FlightTools {

    private final FlightService flightService;

    public FlightTools(FlightService flightService) {
        this.flightService = flightService;
    }

    @Bean
    public ToolCallbackProvider flightToolsProvider(FlightTools flightTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(flightTools)
                .build();
    }

    @Tool(description = """
        Find flights between two cities.
        Requires: departureCity - Name of the departure city,
                 arrivalCity - Name of the arrival city.
        Returns: List of available flights sorted by price from lowest to highest.
        Errors: NOT_FOUND if no airports found in specified cities.
        """)
    public List<Flight> findFlightsByRoute(String departureCity, String arrivalCity) {
        return flightService.findFlightsByRoute(departureCity, arrivalCity);
    }

    @Tool(description = """
        Find flight details by flight number.
        Requires: flightNumber - The unique identifier of the flight (e.g., AA1234).
        Returns: Complete flight details including departure/arrival airports, times, and pricing.
        Errors: NOT_FOUND if flight doesn't exist with the specified number.
        """)
    public Flight findFlightByNumber(String flightNumber) {
        return flightService.findByFlightNumber(flightNumber);
    }
}
