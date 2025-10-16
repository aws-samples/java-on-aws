package com.example.travel.transportation;

import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * This class provides tool-annotated methods for AI consumption
 * while delegating actual business logic to AirportService
 */
@Component
public class AirportTools {

    private final AirportService airportService;

    public AirportTools(AirportService airportService) {
        this.airportService = airportService;
    }

    @Bean
    public ToolCallbackProvider airportToolsProvider(AirportTools airportTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(airportTools)
                .build();
    }

    @Tool(description = """
        Find airports by city name.
        Requires: city - Name of the city to search for airports.
        Returns: List of airports in the specified city.
        Errors: None. Returns empty list if no airports found.
        """)
    public List<Airport> findAirportsByCity(String city) {
        return airportService.findByCity(city);
    }

    @Tool(description = """
        Find airport details by IATA code.
        Requires: airportCode - 3-letter IATA airport code.
        Returns: Complete airport details including name, city, and country.
        Errors: NOT_FOUND if airport doesn't exist with the specified code.
        """)
    public Airport findAirportByCode(String airportCode) {
        return airportService.findByAirportCode(airportCode);
    }
}
