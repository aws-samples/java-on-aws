package com.example.travel.transportation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

@RestController
@RequestMapping("api/flights")
class FlightController {
    private static final Logger logger = LoggerFactory.getLogger(FlightController.class);
    private final FlightService flightService;

    FlightController(FlightService flightService) {
        this.flightService = flightService;
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<Flight> search(
            @RequestParam(required = false) String departureCity,
            @RequestParam(required = false) String arrivalCity,
            @RequestParam(required = false) String flightNumber) {

        if (departureCity != null && arrivalCity != null) {
            logger.info("Finding flights from city {} to city {}", departureCity, arrivalCity);
            return flightService.findFlightsByRoute(departureCity, arrivalCity);
        } else if (flightNumber != null) {
            logger.info("Finding flight with number: {}", flightNumber);
            List<Flight> result = new ArrayList<>();
            try {
                result.add(flightService.findByFlightNumber(flightNumber));
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
    Flight getFlight(@PathVariable String id) {
        logger.info("Getting flight with id: {}", id);
        return flightService.getFlight(id);
    }
}
