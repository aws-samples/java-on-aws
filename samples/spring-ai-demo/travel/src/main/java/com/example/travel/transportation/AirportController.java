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
@RequestMapping("api/airports")
class AirportController {
    private static final Logger logger = LoggerFactory.getLogger(AirportController.class);
    private final AirportService airportService;

    AirportController(AirportService airportService) {
        this.airportService = airportService;
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    List<Airport> search(@RequestParam(required = false) String city,
                         @RequestParam(required = false) String code) {
        if (city != null) {
            logger.info("Finding airports in city: {}", city);
            return airportService.findByCity(city);
        } else if (code != null) {
            logger.info("Finding airport with code: {}", code);
            List<Airport> result = new ArrayList<>();
            try {
                result.add(airportService.findByAirportCode(code));
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
    Airport getAirport(@PathVariable String id) {
        logger.info("Getting airport with id: {}", id);
        return airportService.getAirport(id);
    }
}
