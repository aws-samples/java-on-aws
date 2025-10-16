package com.example.travel.accommodations;

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
@RequestMapping("api/hotel-bookings")
class HotelBookingController {
    private static final Logger logger = LoggerFactory.getLogger(HotelBookingController.class);
    private final HotelBookingService bookingService;
    private final HotelService hotelService;

    HotelBookingController(HotelBookingService bookingService, HotelService hotelService) {
        this.bookingService = bookingService;
        this.hotelService = hotelService;
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<HotelBooking> search(@RequestParam(required = false) String bookingReference) {
        if (bookingReference != null) {
            logger.info("Finding hotel booking with reference: {}", bookingReference);
            List<HotelBooking> result = new ArrayList<>();
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
    HotelBooking getBooking(@PathVariable String id) {
        logger.info("Getting hotel booking with id: {}", id);
        return bookingService.getBooking(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    HotelBooking createBooking(@Valid @RequestBody HotelBooking hotelBooking) {
        // Get hotel name for logging if possible
        String hotelName = "Unknown";
        try {
            Hotel hotel = hotelService.getHotel(hotelBooking.getHotelId());
            hotelName = hotel.getHotelName();
        } catch (Exception e) {
            // Ignore exception, just for logging purposes
        }

        logger.info("Creating hotel booking for hotel ID: {}, hotel name: {}, customer: {}, check-in: {}",
            hotelBooking.getHotelId(), hotelName, hotelBooking.getCustomerName(), hotelBooking.getCheckInDate());

        return bookingService.createBooking(hotelBooking);
    }

    @PutMapping("/{bookingReference}")
    @ResponseStatus(HttpStatus.OK)
    HotelBooking updateBooking(@PathVariable String bookingReference, @Valid @RequestBody HotelBooking hotelBooking) {
        logger.info("Updating hotel booking: {}", bookingReference);
        hotelBooking.setBookingReference(bookingReference);
        return bookingService.updateBooking(hotelBooking);
    }

    @PutMapping("/{bookingReference}/confirm")
    @ResponseStatus(HttpStatus.OK)
    HotelBooking confirmBooking(@PathVariable String bookingReference) {
        logger.info("Confirming hotel booking: {}", bookingReference);
        return bookingService.confirmBooking(bookingReference);
    }

    @PutMapping("/{bookingReference}/cancel")
    @ResponseStatus(HttpStatus.OK)
    HotelBooking cancelBooking(@PathVariable String bookingReference) {
        logger.info("Cancelling hotel booking: {}", bookingReference);
        return bookingService.cancelBooking(bookingReference);
    }
}
