package com.example.travel.accommodations;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;

/**
 * Service responsible for hotel booking operations.
 * Follows DDD principles by encapsulating domain logic related to bookings.
 */
@Service
public class HotelBookingService {
    private static final Logger logger = LoggerFactory.getLogger(HotelBookingService.class);
    private final HotelBookingRepository bookingRepository;
    private final HotelRepository hotelRepository;

    public HotelBookingService(HotelBookingRepository bookingRepository, HotelRepository hotelRepository) {
        this.bookingRepository = bookingRepository;
        this.hotelRepository = hotelRepository;
    }

    /**
     * Get a hotel booking by its ID
     *
     * @param id The unique booking ID
     * @return The hotel booking
     * @throws ResponseStatusException if booking not found
     */
    @Transactional(readOnly = true)
    public HotelBooking getBooking(String id) {
        return bookingRepository.findById(id)
            .orElseThrow(() -> {
                logger.warn("Hotel Booking not found with id: {}", id);
                return new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Hotel Booking not found with id: " + id);
            });
    }

    /**
     * Find a hotel booking by its reference code
     *
     * @param bookingReference The unique booking reference
     * @return The hotel booking
     * @throws ResponseStatusException if booking not found
     */
    @Transactional(readOnly = true)
    public HotelBooking findByBookingReference(String bookingReference) {
        return bookingRepository.findByBookingReference(bookingReference)
            .orElseThrow(() -> {
                logger.warn("Hotel Booking not found with reference: {}", bookingReference);
                return new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Hotel Booking not found with reference: " + bookingReference);
            });
    }

    /**
     * Create a new hotel booking
     *
     * @param booking The booking to create
     * @return The saved booking with generated ID and reference
     */
    @Transactional
    public HotelBooking createBooking(HotelBooking booking) {
        // Get and validate hotel
        Hotel hotel = findAndValidateHotel(booking.getHotelId(), booking.getNumberOfRooms());

        // Prepare booking data
        enrichBookingData(booking, hotel);

        // Save booking
        HotelBooking savedBooking = bookingRepository.save(booking);

        // Update hotel inventory
        updateHotelInventory(hotel, -booking.getNumberOfRooms());

        logger.info("Created hotel booking: {}, hotel: {}, {} night(s), total: {} {}",
            savedBooking.getBookingReference(),
            hotel.getHotelName(),
            ChronoUnit.DAYS.between(booking.getCheckInDate(), booking.getCheckOutDate()),
            savedBooking.getTotalPrice(),
            savedBooking.getCurrency());

        return savedBooking;
    }

    /**
     * Update an existing hotel booking
     *
     * @param updatedBooking The booking with updated information
     * @return The updated booking
     */
    @Transactional
    public HotelBooking updateBooking(HotelBooking updatedBooking) {
        // Find existing booking
        HotelBooking existingBooking = findByBookingReference(updatedBooking.getBookingReference());

        // Preserve the ID field
        updatedBooking.setId(existingBooking.getId());

        // Handle hotel change if needed
        handleHotelChange(existingBooking, updatedBooking);

        // Preserve creation timestamp and update the updated timestamp
        updatedBooking.setCreatedAt(existingBooking.getCreatedAt());
        updatedBooking.setUpdatedAt(LocalDateTime.now());

        HotelBooking savedBooking = bookingRepository.save(updatedBooking);

        logger.info("Updated hotel booking: {}, hotel: {}, check-in: {}, check-out: {}",
            savedBooking.getBookingReference(),
            savedBooking.getHotelId(),
            savedBooking.getCheckInDate(),
            savedBooking.getCheckOutDate());

        return savedBooking;
    }

    /**
     * Confirm a pending hotel booking
     *
     * @param bookingReference The booking reference to confirm
     * @return The confirmed booking
     */
    @Transactional
    public HotelBooking confirmBooking(String bookingReference) {
        HotelBooking booking = findByBookingReference(bookingReference);

        if (booking.getStatus() != HotelBooking.BookingStatus.PENDING) {
            logger.warn("Failed to confirm Hotel booking: booking {} has invalid status: {}",
                bookingReference, booking.getStatus());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Only pending bookings can be confirmed. Current status: " + booking.getStatus());
        }

        booking.setStatus(HotelBooking.BookingStatus.CONFIRMED);
        booking.setUpdatedAt(LocalDateTime.now());

        HotelBooking confirmedBooking = bookingRepository.save(booking);

        logger.info("Confirmed hotel booking: {}, hotel: {}, check-in: {}",
            confirmedBooking.getBookingReference(),
            confirmedBooking.getHotelId(),
            confirmedBooking.getCheckInDate());

        return confirmedBooking;
    }

    /**
     * Cancel an existing hotel booking
     *
     * @param bookingReference The booking reference to cancel
     * @return The cancelled booking
     */
    @Transactional
    public HotelBooking cancelBooking(String bookingReference) {
        HotelBooking booking = findByBookingReference(bookingReference);

        validateCancellable(booking);

        booking.setStatus(HotelBooking.BookingStatus.CANCELLED);
        booking.setUpdatedAt(LocalDateTime.now());

        // Return rooms to hotel inventory
        returnRoomsToInventory(booking);

        HotelBooking cancelledBooking = bookingRepository.save(booking);

        logger.info("Cancelled hotel booking: {}, hotel: {}, check-in: {}, rooms returned: {}",
            cancelledBooking.getBookingReference(),
            cancelledBooking.getHotelId(),
            cancelledBooking.getCheckInDate(),
            booking.getNumberOfRooms());

        return cancelledBooking;
    }

    /**
     * Find hotels by name
     *
     * @param hotelName The hotel name to search for
     * @return List of matching hotels
     */
    @Transactional(readOnly = true)
    public List<Hotel> findHotelsByName(String hotelName) {
        List<Hotel> hotels = hotelRepository.findByHotelNameContainingIgnoreCase(hotelName);
        if (hotels.isEmpty()) {
            logger.warn("No hotels found with name containing: {}", hotelName);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No hotels found with name containing: " + hotelName);
        }
        return hotels;
    }

    // Private helper methods

    /**
     * Find and validate a hotel for booking
     */
    private Hotel findAndValidateHotel(String hotelId, int requiredRooms) {
        Hotel hotel = hotelRepository.findById(hotelId)
            .orElseThrow(() -> {
                logger.warn("Failed to create Hotel booking: no hotel found with ID: {}", hotelId);
                return new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "No hotel found with ID: " + hotelId);
            });

        // Check if hotel is active
        if (hotel.getStatus() != Hotel.HotelStatus.ACTIVE) {
            logger.warn("Failed to create Hotel booking: hotel with ID {} is not active", hotelId);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Hotel with ID " + hotelId + " is not active");
        }

        // Check if hotel has enough rooms
        if (hotel.getAvailableRooms() < requiredRooms) {
            logger.warn("Failed to create Hotel booking: not enough rooms available in hotel with ID: {}", hotelId);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Not enough rooms available in hotel with ID: " + hotelId);
        }

        return hotel;
    }

    /**
     * Enrich booking data with calculated fields
     */
    private void enrichBookingData(HotelBooking booking, Hotel hotel) {
        // Calculate total price if not provided
        if (booking.getTotalPrice() == null) {
            long nights = ChronoUnit.DAYS.between(booking.getCheckInDate(), booking.getCheckOutDate());
            BigDecimal totalPrice = hotel.getPricePerNight()
                .multiply(BigDecimal.valueOf(nights))
                .multiply(BigDecimal.valueOf(booking.getNumberOfRooms()));
            booking.setTotalPrice(totalPrice);
        }

        // Set currency if not provided
        if (booking.getCurrency() == null) {
            booking.setCurrency(hotel.getCurrency());
        }

        // Set status if not provided
        if (booking.getStatus() == null) {
            booking.setStatus(HotelBooking.BookingStatus.PENDING);
        }

        // Set timestamps
        LocalDateTime now = LocalDateTime.now();
        if (booking.getCreatedAt() == null) {
            booking.setCreatedAt(now);
        }
        booking.setUpdatedAt(now);
    }

    /**
     * Update hotel inventory by adding or removing rooms
     */
    @Transactional
    private void updateHotelInventory(Hotel hotel, int roomDelta) {
        hotel.setAvailableRooms(hotel.getAvailableRooms() + roomDelta);
        hotelRepository.save(hotel);
    }

    /**
     * Handle hotel change during booking update
     */
    private void handleHotelChange(HotelBooking existingBooking, HotelBooking updatedBooking) {
        // Check if hotel ID is being changed
        if (!existingBooking.getHotelId().equals(updatedBooking.getHotelId())) {
            // Validate new hotel
            Hotel newHotel = findAndValidateHotel(updatedBooking.getHotelId(), updatedBooking.getNumberOfRooms());

            // Return rooms to old hotel
            hotelRepository.findById(existingBooking.getHotelId())
                .ifPresent(oldHotel -> updateHotelInventory(oldHotel, existingBooking.getNumberOfRooms()));

            // Take rooms from new hotel
            updateHotelInventory(newHotel, -updatedBooking.getNumberOfRooms());
        } else if (existingBooking.getNumberOfRooms() != updatedBooking.getNumberOfRooms()) {
            // Handle room count change for same hotel
            hotelRepository.findById(existingBooking.getHotelId())
                .ifPresent(hotel -> {
                    int roomDifference = existingBooking.getNumberOfRooms() - updatedBooking.getNumberOfRooms();
                    updateHotelInventory(hotel, roomDifference);
                });
        }
    }

    /**
     * Validate if a booking can be cancelled
     */
    private void validateCancellable(HotelBooking booking) {
        if (booking.getStatus() == HotelBooking.BookingStatus.CANCELLED) {
            logger.warn("Failed to cancel Hotel booking: booking {} is already cancelled", booking.getBookingReference());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Booking is already cancelled");
        }

        if (booking.getStatus() == HotelBooking.BookingStatus.CHECKED_IN ||
            booking.getStatus() == HotelBooking.BookingStatus.CHECKED_OUT) {
            logger.warn("Failed to cancel Hotel booking: booking {} has invalid status: {}",
                booking.getBookingReference(), booking.getStatus());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Cannot cancel booking with status: " + booking.getStatus());
        }
    }

    /**
     * Delete a hotel booking
     *
     * @param bookingReference The booking reference to delete
     */
    @Transactional
    public void deleteBooking(String bookingReference) {
        HotelBooking booking = getBooking(bookingReference);

        // Return rooms to hotel inventory if booking is not cancelled
        if (booking.getStatus() != HotelBooking.BookingStatus.CANCELLED) {
            returnRoomsToInventory(booking);
        }

        bookingRepository.delete(booking);

        logger.info("Deleted hotel booking: {}, hotel: {}, check-in: {}",
            booking.getBookingReference(), booking.getHotelId(), booking.getCheckInDate());
    }

    /**
     * Return rooms to hotel inventory when cancelling a booking
     */
    private void returnRoomsToInventory(HotelBooking booking) {
        hotelRepository.findById(booking.getHotelId())
            .ifPresent(hotel -> updateHotelInventory(hotel, booking.getNumberOfRooms()));
    }
}
