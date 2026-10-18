package com.example.backoffice.trip;

// >> Spring AI tool annotations: `@Tool` for methods, `@ToolParam` for parameters
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.ai.tool.ToolCallbackProvider;
// <<
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.List;

@Component
public class TripTools {

    private final TripService service;

    public TripTools(TripService service) {
        this.service = service;
    }

    // >> The `ToolCallbackProvider` bean registers all `@Tool` methods with the MCP server
    @Bean
    public ToolCallbackProvider tripToolsProvider(TripTools tripTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(tripTools)
                .build();
                // <<
    }

    // >> The tool description helps the model decide when to call the tool
    @Tool(description = "Register a new business trip. Returns trip reference for tracking.")
    // <<
    public Trip registerTrip(
            // >> `@ToolParam` descriptions guide the model when it extracts parameters from the prompt
            @ToolParam(description = "User ID") String userId,
            @ToolParam(description = "Departure date (YYYY-MM-DD)") LocalDate departureDate,
            @ToolParam(description = "Return date (YYYY-MM-DD)") LocalDate returnDate,
            @ToolParam(description = "Origin city") String origin,
            @ToolParam(description = "Destination city") String destination,
            @ToolParam(description = "Trip purpose") String purpose) {
            // <<
        return service.registerTrip(userId, departureDate, returnDate, origin, destination, purpose);
    }

    @Tool(description = "Get all business trips registered by a user")
    public List<Trip> getTrips(@ToolParam(description = "User ID") String userId) {
        return service.getTrips(userId);
    }

    @Tool(description = "Get trip details by reference number")
    public Trip getTrip(@ToolParam(description = "Trip reference (TRP-XXXXXXXX)") String tripReference) {
        return service.getTrip(tripReference);
    }

    @Tool(description = "Cancel a planned trip")
    public Trip cancelTrip(@ToolParam(description = "Trip reference (TRP-XXXXXXXX)") String tripReference) {
        return service.cancelTrip(tripReference);
    }
}
