package com.example.travel.transportation;

import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * This class provides tool-annotated methods for AI consumption
 * while delegating actual business logic to FlightBookingService
 */
@Component
public class FlightBookingTools {

    private final FlightBookingService bookingService;

    public FlightBookingTools(FlightBookingService bookingService) {
        this.bookingService = bookingService;
    }

    @Bean
    public ToolCallbackProvider flightBookingToolsProvider(FlightBookingTools flightBookingTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(flightBookingTools)
                .build();
    }

    @Tool(description = """
        Find flight booking by reference code.
        Requires: bookingReference - The unique booking identifier.
        Returns: Complete booking details including flight information and passenger data.
        Errors: NOT_FOUND if booking doesn't exist.
        """)
    public FlightBooking findFlightBookingByBookingReference(String bookingReference) {
        return bookingService.findByBookingReference(bookingReference);
    }

    @Tool(description = """
        Create a new flight booking.
        Requires: flightNumber - Flight number for selected flight from findFlightsByRoute,
                 flightDate - Travel date (YYYY-MM-DD),
                 customerName - Full name of customer,
                 customerEmail - Valid email address,
                 numberOfPassengers - Number of seats to book (1-9).
        Returns: Flight Booking confirmation with reference code.
        Errors: NOT_FOUND if flight doesn't exist, BAD_REQUEST if not enough seats available.
        """)
    public FlightBooking createFlightBooking(String flightNumber, LocalDate flightDate,
                                      String customerName, String customerEmail,
                                      Integer numberOfPassengers) {
        return bookingService.createBookingByFlightNumber(flightNumber, flightDate,
                                                customerName, customerEmail, numberOfPassengers);
    }

    @Tool(description = """
        Confirm a pending flight booking.
        Requires: bookingReference - The unique booking identifier.
        Returns: Updated Flight booking with CONFIRMED status.
        Errors: NOT_FOUND if booking doesn't exist,
               BAD_REQUEST if booking is already confirmed, cancelled, or completed.
        """)
    public FlightBooking confirmFlightBooking(String bookingReference) {
        return bookingService.confirmBooking(bookingReference);
    }

    @Tool(description = """
        Cancel an existing flight booking.
        Requires: bookingReference - The unique Flight booking identifier.
        Returns: Updated booking with CANCELLED status.
        Errors: NOT_FOUND if booking doesn't exist,
               BAD_REQUEST if booking is already cancelled or completed.
        """)
    public FlightBooking cancelFlightBooking(String bookingReference) {
        return bookingService.cancelBooking(bookingReference);
    }
}
