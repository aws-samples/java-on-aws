package com.example.travel.transportation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import jakarta.validation.Valid;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

@RestController
@RequestMapping("api/flight-bookings")
class FlightBookingController {
    private static final Logger logger = LoggerFactory.getLogger(FlightBookingController.class);
    private final FlightBookingService bookingService;

    FlightBookingController(FlightBookingService bookingService) {
        this.bookingService = bookingService;
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<FlightBooking> search(@RequestParam(required = false) String bookingReference) {
        if (bookingReference != null) {
            logger.info("Finding flight booking with reference: {}", bookingReference);
            List<FlightBooking> result = new ArrayList<>();
            try {
                result.add(bookingService.findByBookingReference(bookingReference));
            } catch (ResponseStatusException e) {
                // Return empty list if not found
            }
            return result;
        } else {
            return Collections.emptyList();
        }
    }

    @GetMapping("/{id}")
    @ResponseStatus(HttpStatus.OK)
    FlightBooking getBooking(@PathVariable String id) {
        logger.info("Getting flight booking with id: {}", id);
        return bookingService.getBooking(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    FlightBooking createBooking(@Valid @RequestBody FlightBooking booking) {
        logger.info("Creating flight booking for flight id: {}, customer: {}, seats: {}",
            booking.getFlightId(), booking.getCustomerName(), booking.getNumberOfPassengers());
        return bookingService.createBooking(booking);
    }

    @PutMapping("/{bookingReference}/confirm")
    @ResponseStatus(HttpStatus.OK)
    FlightBooking confirmBooking(@PathVariable String bookingReference) {
        logger.info("Confirming flight booking: {}", bookingReference);
        return bookingService.confirmBooking(bookingReference);
    }

    @PutMapping("/{bookingReference}/cancel")
    @ResponseStatus(HttpStatus.OK)
    FlightBooking cancelBooking(@PathVariable String bookingReference) {
        logger.info("Cancelling flight booking: {}", bookingReference);
        return bookingService.cancelBooking(bookingReference);
    }
}
