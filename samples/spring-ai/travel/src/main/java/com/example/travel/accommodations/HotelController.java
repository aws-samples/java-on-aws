package com.example.travel.accommodations;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.Collections;
import java.util.List;

@RestController
@RequestMapping("api/hotels")
class HotelController {
    private static final Logger logger = LoggerFactory.getLogger(HotelController.class);
    private final HotelService hotelService;

    HotelController(HotelService hotelService) {
        this.hotelService = hotelService;
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<Hotel> search(
            @RequestParam(required = false) String city,
            @RequestParam(required = false) String name,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate checkInDate,
            @RequestParam(required = false) Integer numberOfNights) {

        if (city != null && checkInDate != null && numberOfNights != null) {
            logger.info("Finding hotels in city: {}, check-in: {}, nights: {}",
                city, checkInDate, numberOfNights);
            return hotelService.findHotelsByCity(city, checkInDate, numberOfNights);
        } else if (name != null) {
            logger.info("Finding hotels by name: {}", name);
            return hotelService.findHotelsByName(name);
        } else {
            return Collections.emptyList();
        }
    }

    @GetMapping("/{id}")
    @ResponseStatus(HttpStatus.OK)
    Hotel getHotel(@PathVariable String id) {
        logger.info("Getting hotel with ID: {}", id);
        return hotelService.getHotel(id);
    }
}
