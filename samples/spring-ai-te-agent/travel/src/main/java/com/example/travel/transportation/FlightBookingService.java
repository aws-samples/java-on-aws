package com.example.travel.transportation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Optional;

@Service
public class FlightBookingService {
    private static final Logger logger = LoggerFactory.getLogger(FlightBookingService.class);
    private final FlightBookingRepository bookingRepository;
    private final FlightRepository flightRepository;

    FlightBookingService(FlightBookingRepository bookingRepository, FlightRepository flightRepository) {
        this.bookingRepository = bookingRepository;
        this.flightRepository = flightRepository;
    }

    @Transactional(readOnly = true)
    public FlightBooking getBooking(String id) {
        return bookingRepository.findById(id)
            .orElseThrow(() -> {
                logger.warn("Flight Booking not found with id: {}", id);
                return new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Flight Booking not found with id: " + id);
            });
    }

    @Transactional(readOnly = true)
    public FlightBooking findByBookingReference(String bookingReference) {
        Optional<FlightBooking> booking = bookingRepository.findByBookingReference(bookingReference);
        if (booking.isEmpty()) {
            logger.warn("Flight Booking not found with reference: {}", bookingReference);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Flight Booking not found with reference: " + bookingReference);
        }

        logger.info("Retrieved Flight booking: {}, customer: {}",
            bookingReference, booking.get().getCustomerName());

        return booking.get();
    }

    @Transactional
    public FlightBooking createBooking(FlightBooking booking) {
        // Validate flight exists
        Flight flight = getFlightByIdOrThrow(booking.getFlightId());

        // Check if flight has enough available seats
        if (flight.getAvailableSeats() < booking.getNumberOfPassengers()) {
            logger.warn("Failed to create Flight booking: not enough seats available for flight {}: requested {}, available {}",
                flight.getFlightNumber(), booking.getNumberOfPassengers(), flight.getAvailableSeats());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Not enough seats available. Requested: " + booking.getNumberOfPassengers() +
                ", Available: " + flight.getAvailableSeats());
        }

        // Calculate total price
        BigDecimal totalPrice = flight.getPrice().multiply(BigDecimal.valueOf(booking.getNumberOfPassengers()));
        booking.setTotalPrice(totalPrice);
        booking.setCurrency(flight.getCurrency());

        // Save booking
        FlightBooking savedBooking = bookingRepository.save(booking);

        // Update available seats
        flight.setAvailableSeats(flight.getAvailableSeats() - booking.getNumberOfPassengers());
        flightRepository.save(flight);

        logger.info("Created flight booking: {}, flight: {}, customer: {}, seats: {}, total: {} {}",
            savedBooking.getBookingReference(), flight.getFlightNumber(), booking.getCustomerName(),
            booking.getNumberOfPassengers(), totalPrice, flight.getCurrency());

        return savedBooking;
    }

    @Transactional
    public FlightBooking createBookingByFlightNumber(String flightNumber, LocalDate flightDate,
                                      String customerName, String customerEmail,
                                      Integer numberOfPassengers) {
        // Find flight by number
        Flight flight = getFlightByNumberOrThrow(flightNumber);

        // Create booking object
        FlightBooking booking = new FlightBooking();
        booking.setFlightId(flight.getId());
        booking.setFlightDate(flightDate);
        booking.setCustomerName(customerName);
        booking.setCustomerEmail(customerEmail);
        booking.setNumberOfPassengers(numberOfPassengers);

        // Use the common create method
        return createBooking(booking);
    }

    @Transactional
    public FlightBooking confirmBooking(String bookingReference) {
        FlightBooking booking = findByBookingReference(bookingReference);

        // Check if booking can be confirmed
        if (booking.getStatus() == FlightBooking.BookingStatus.CONFIRMED) {
            logger.warn("Failed to confirm Flight booking: booking {} is already confirmed", bookingReference);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Booking is already confirmed");
        }

        if (booking.getStatus() == FlightBooking.BookingStatus.CANCELLED) {
            logger.warn("Failed to confirm Flight booking: booking {} is cancelled", bookingReference);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Cannot confirm a cancelled booking");
        }

        if (booking.getStatus() == FlightBooking.BookingStatus.COMPLETED) {
            logger.warn("Failed to confirm Flight booking: booking {} is completed", bookingReference);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Cannot confirm a completed booking");
        }

        // Update booking status
        booking.setStatus(FlightBooking.BookingStatus.CONFIRMED);

        // Save updated booking
        FlightBooking confirmedBooking = bookingRepository.save(booking);

        logger.info("Confirmed flight booking: {}, customer: {}, seats: {}",
            bookingReference, booking.getCustomerName(), booking.getNumberOfPassengers());

        return confirmedBooking;
    }

    @Transactional
    public FlightBooking cancelBooking(String bookingReference) {
        FlightBooking booking = findByBookingReference(bookingReference);

        // Check if booking can be cancelled
        if (booking.getStatus() == FlightBooking.BookingStatus.CANCELLED) {
            logger.warn("Failed to cancel Flight booking: booking {} is already cancelled", bookingReference);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Booking is already cancelled");
        }

        if (booking.getStatus() == FlightBooking.BookingStatus.COMPLETED) {
            logger.warn("Failed to cancel Flight booking: booking {} is completed", bookingReference);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Cannot cancel a completed booking");
        }

        // Update booking status
        booking.setStatus(FlightBooking.BookingStatus.CANCELLED);

        // Return seats to flight
        Flight flight = getFlightByIdOrThrow(booking.getFlightId());
        flight.setAvailableSeats(flight.getAvailableSeats() + booking.getNumberOfPassengers());
        flightRepository.save(flight);

        // Save updated booking
        FlightBooking cancelledBooking = bookingRepository.save(booking);

        logger.info("Cancelled flight booking: {}, flight: {}, customer: {}, seats returned: {}",
            bookingReference, flight.getFlightNumber(), booking.getCustomerName(),
            booking.getNumberOfPassengers());

        return cancelledBooking;
    }

    @Transactional
    public FlightBooking updateBooking(String id, FlightBooking booking) {
        FlightBooking existingBooking = getBooking(id);

        // Preserve the ID and booking reference
        booking.setId(id);
        booking.setBookingReference(existingBooking.getBookingReference());

        // If flight is being changed, validate new flight and check seat availability
        if (!existingBooking.getFlightId().equals(booking.getFlightId())) {
            Flight newFlight = getFlightByIdOrThrow(booking.getFlightId());

            // Check if new flight has enough seats
            if (newFlight.getAvailableSeats() < booking.getNumberOfPassengers()) {
                logger.warn("Failed to update Flight booking: not enough seats available on new flight");
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Not enough seats available on new flight. Available: " + newFlight.getAvailableSeats());
            }

            // Return seats to old flight
            Flight oldFlight = getFlightByIdOrThrow(existingBooking.getFlightId());
            oldFlight.setAvailableSeats(oldFlight.getAvailableSeats() + existingBooking.getNumberOfPassengers());
            flightRepository.save(oldFlight);

            // Take seats from new flight
            newFlight.setAvailableSeats(newFlight.getAvailableSeats() - booking.getNumberOfPassengers());
            flightRepository.save(newFlight);

            // Update price based on new flight
            booking.setTotalPrice(newFlight.getPrice().multiply(BigDecimal.valueOf(booking.getNumberOfPassengers())));
            booking.setCurrency(newFlight.getCurrency());
        }
        // If only passenger count is changing on same flight
        else if (existingBooking.getNumberOfPassengers() != booking.getNumberOfPassengers()) {
            Flight flight = getFlightByIdOrThrow(booking.getFlightId());

            // Calculate seat difference
            int seatDifference = booking.getNumberOfPassengers() - existingBooking.getNumberOfPassengers();

            // If adding seats, check availability
            if (seatDifference > 0 && flight.getAvailableSeats() < seatDifference) {
                logger.warn("Failed to update Flight booking: not enough additional seats available");
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Not enough additional seats available. Needed: " + seatDifference +
                    ", Available: " + flight.getAvailableSeats());
            }

            // Update flight seat count
            flight.setAvailableSeats(flight.getAvailableSeats() - seatDifference);
            flightRepository.save(flight);

            // Update price
            booking.setTotalPrice(flight.getPrice().multiply(BigDecimal.valueOf(booking.getNumberOfPassengers())));
            booking.setCurrency(flight.getCurrency());
        }

        FlightBooking updatedBooking = bookingRepository.save(booking);
        logger.info("Updated flight booking: {}", updatedBooking.getBookingReference());
        return updatedBooking;
    }

    @Transactional
    public void deleteBooking(String id) {
        FlightBooking booking = getBooking(id);

        // Return seats to flight if booking is not cancelled
        if (booking.getStatus() != FlightBooking.BookingStatus.CANCELLED) {
            Flight flight = getFlightByIdOrThrow(booking.getFlightId());
            flight.setAvailableSeats(flight.getAvailableSeats() + booking.getNumberOfPassengers());
            flightRepository.save(flight);
        }

        bookingRepository.deleteById(id);
        logger.info("Deleted flight booking: {}", booking.getBookingReference());
    }

    private Flight getFlightByIdOrThrow(String id) {
        return flightRepository.findById(id)
            .orElseThrow(() -> {
                logger.warn("Flight not found with id: {}", id);
                return new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Flight not found with id: " + id);
            });
    }

    private Flight getFlightByNumberOrThrow(String flightNumber) {
        return flightRepository.findByFlightNumber(flightNumber)
            .orElseThrow(() -> {
                logger.warn("Flight not found with number: {}", flightNumber);
                return new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Flight not found with number: " + flightNumber);
            });
    }
}
