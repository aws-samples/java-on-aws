package com.example.travel.transportation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.List;
import java.util.Optional;

@Service
public class AirportService {
    private static final Logger logger = LoggerFactory.getLogger(AirportService.class);
    private final AirportRepository airportRepository;

    AirportService(AirportRepository airportRepository) {
        this.airportRepository = airportRepository;
    }

    @Transactional(readOnly = true)
    public List<Airport> findByCity(String city) {
        List<Airport> airports = airportRepository.findByCityContainingIgnoreCase(city);
        logger.info("Found {} airports in city: {}", airports.size(), city);
        return airports;
    }

    @Transactional(readOnly = true)
    public Airport findByAirportCode(String airportCode) {
        Optional<Airport> airport = airportRepository.findByAirportCode(airportCode);
        if (airport.isEmpty()) {
            logger.warn("Airport not found with code: {}", airportCode);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Airport not found with code: " + airportCode);
        }
        logger.info("Found airport: {} ({})", airport.get().getAirportName(), airportCode);
        return airport.get();
    }

    @Transactional(readOnly = true)
    public Airport getAirport(String id) {
        return airportRepository.findById(id)
            .orElseThrow(() -> {
                logger.warn("Airport not found with id: {}", id);
                return new ResponseStatusException(HttpStatus.NOT_FOUND, "Airport not found with id: " + id);
            });
    }

    @Transactional
    public Airport createAirport(Airport airport) {
        // Check if airport with same code already exists
        Optional<Airport> existingAirport = airportRepository.findByAirportCode(airport.getAirportCode());
        if (existingAirport.isPresent()) {
            logger.warn("Airport already exists with code: {}", airport.getAirportCode());
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Airport already exists with code: " + airport.getAirportCode());
        }

        Airport savedAirport = airportRepository.save(airport);
        logger.info("Created airport: {} ({})", savedAirport.getAirportName(), savedAirport.getAirportCode());
        return savedAirport;
    }

    @Transactional
    public Airport updateAirport(String id, Airport airport) {
        Airport existingAirport = getAirport(id);

        // If airport code is being changed, check that new code doesn't conflict
        if (!existingAirport.getAirportCode().equals(airport.getAirportCode())) {
            Optional<Airport> conflictingAirport = airportRepository.findByAirportCode(airport.getAirportCode());
            if (conflictingAirport.isPresent()) {
                logger.warn("Cannot update airport: code {} already in use", airport.getAirportCode());
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Airport code already in use: " + airport.getAirportCode());
            }
        }

        // Preserve the ID
        airport.setId(id);

        Airport updatedAirport = airportRepository.save(airport);
        logger.info("Updated airport: {} ({})", updatedAirport.getAirportName(), updatedAirport.getAirportCode());
        return updatedAirport;
    }

    @Transactional
    public void deleteAirport(String id) {
        if (!airportRepository.existsById(id)) {
            logger.warn("Cannot delete: airport not found with id: {}", id);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Airport not found with id: " + id);
        }

        airportRepository.deleteById(id);
        logger.info("Deleted airport with id: {}", id);
    }
}
