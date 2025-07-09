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
 * while delegating actual business logic to HotelBookingService
 */
@Component
public class HotelBookingTools {

    private final HotelBookingService bookingService;
    private final HotelService hotelService;

    public HotelBookingTools(HotelBookingService bookingService, HotelService hotelService) {
        this.bookingService = bookingService;
        this.hotelService = hotelService;
    }

    @Bean
    public ToolCallbackProvider hotelBookingToolsProvider(HotelBookingTools hotelBookingTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(hotelBookingTools)
                .build();
    }

    @Tool(description = """
        Find hotel booking by reference code.
        Requires: bookingReference - The unique booking identifier.
        Returns: Complete booking details including hotel information and guest data.
        Errors: NOT_FOUND if booking doesn't exist.
        """)
    public HotelBooking findHotelBookingByBookingReference(String bookingReference) {
        return bookingService.getBooking(bookingReference);
    }

    @Tool(description = """
        Create a new hotel booking by hotel name.
        Requires: hotelName - Name of the hotel to book,
                 customerName - Full name of customer,
                 customerEmail - Valid email address,
                 checkInDate - Arrival date (YYYY-MM-DD),
                 checkOutDate - Departure date (YYYY-MM-DD),
                 numberOfGuests - Number of people staying,
                 numberOfRooms - Number of rooms to book.
        Returns: Hotel Booking confirmation with reference code.
        Errors: NOT_FOUND if hotel doesn't exist,
               BAD_REQUEST if hotel is inactive or not enough rooms available.
        """)
    public HotelBooking createHotelBookingByHotelName(String hotelName, String customerName, String customerEmail,
                                     LocalDate checkInDate, LocalDate checkOutDate,
                                     Integer numberOfGuests, Integer numberOfRooms) {
        List<Hotel> hotels = hotelService.findHotelsByName(hotelName);

        // Find the first active hotel with enough rooms
        Hotel selectedHotel = null;
        for (Hotel hotel : hotels) {
            if (hotel.getStatus() == Hotel.HotelStatus.ACTIVE && hotel.getAvailableRooms() >= numberOfRooms) {
                selectedHotel = hotel;
                break;
            }
        }

        if (selectedHotel == null) {
            if (hotels.stream().noneMatch(h -> h.getStatus() == Hotel.HotelStatus.ACTIVE)) {
                throw new IllegalArgumentException("No active hotels found with name: " + hotelName);
            } else {
                throw new IllegalArgumentException("Not enough rooms available in any hotel with name: " + hotelName);
            }
        }

        // Call the method that accepts hotelId
        return createHotelBookingByHotelId(
            selectedHotel.getId(),
            customerName,
            customerEmail,
            checkInDate,
            checkOutDate,
            numberOfGuests,
            numberOfRooms
        );
    }

    @Tool(description = """
        Create a new hotel booking by hotel ID.
        Requires: hotelId - ID of the hotel to book,
                 customerName - Full name of customer,
                 customerEmail - Valid email address,
                 checkInDate - Arrival date (YYYY-MM-DD),
                 checkOutDate - Departure date (YYYY-MM-DD),
                 numberOfGuests - Number of people staying,
                 numberOfRooms - Number of rooms to book.
        Returns: Hotel Booking confirmation with reference code.
        Errors: NOT_FOUND if hotel doesn't exist,
               BAD_REQUEST if hotel is inactive or not enough rooms available.
        """)
    public HotelBooking createHotelBookingByHotelId(String hotelId, String customerName, String customerEmail,
                                     LocalDate checkInDate, LocalDate checkOutDate,
                                     Integer numberOfGuests, Integer numberOfRooms) {
        // Create a HotelBooking object from the parameters
        HotelBooking booking = new HotelBooking();
        booking.setHotelId(hotelId);
        booking.setCustomerName(customerName);
        booking.setCustomerEmail(customerEmail);
        booking.setCheckInDate(checkInDate);
        booking.setCheckOutDate(checkOutDate);
        booking.setNumberOfGuests(numberOfGuests);
        booking.setNumberOfRooms(numberOfRooms);

        // Use the service to create the booking
        return bookingService.createBooking(booking);
    }

    @Tool(description = """
        Confirm a pending hotel booking.
        Requires: bookingReference - The unique booking identifier.
        Returns: Updated Hotel booking with CONFIRMED status.
        Errors: NOT_FOUND if booking doesn't exist,
               BAD_REQUEST if booking is not in PENDING status.
        """)
    public HotelBooking confirmHotelBooking(String bookingReference) {
        return bookingService.confirmBooking(bookingReference);
    }

    @Tool(description = """
        Cancel an existing hotel booking.
        Requires: bookingReference - The unique booking identifier.
        Returns: Updated Hotel booking with CANCELLED status.
        Errors: NOT_FOUND if booking doesn't exist,
               BAD_REQUEST if booking is already cancelled, checked-in, or checked-out.
        """)
    public HotelBooking cancelHotelBooking(String bookingReference) {
        return bookingService.cancelBooking(bookingReference);
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
}
