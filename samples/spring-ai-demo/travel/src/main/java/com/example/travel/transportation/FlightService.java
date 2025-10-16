package com.example.travel.transportation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
public class FlightService {
    private static final Logger logger = LoggerFactory.getLogger(FlightService.class);
    private final FlightRepository flightRepository;
    private final AirportRepository airportRepository;

    public FlightService(FlightRepository flightRepository, AirportRepository airportRepository) {
        this.flightRepository = flightRepository;
        this.airportRepository = airportRepository;
    }

    @Transactional(readOnly = true)
    public List<Flight> findFlightsByRoute(String departureCity, String arrivalCity) {
        // Find airports in the specified cities
        List<Airport> departureAirports = airportRepository.findByCityContainingIgnoreCase(departureCity);
        List<Airport> arrivalAirports = airportRepository.findByCityContainingIgnoreCase(arrivalCity);

        if (departureAirports.isEmpty()) {
            logger.warn("No airports found in departure city: {}", departureCity);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No airports found in departure city: " + departureCity);
        }

        if (arrivalAirports.isEmpty()) {
            logger.warn("No airports found in arrival city: {}", arrivalCity);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No airports found in arrival city: " + arrivalCity);
        }

        // Find flights between any airport in departure city and any airport in arrival city
        List<Flight> allFlights = new ArrayList<>();
        for (Airport depAirport : departureAirports) {
            for (Airport arrAirport : arrivalAirports) {
                List<Flight> flights = flightRepository.findByDepartureAirportAndArrivalAirportAndStatus(
                    depAirport.getAirportCode(), arrAirport.getAirportCode(), Flight.FlightStatus.SCHEDULED);
                allFlights.addAll(flights);
            }
        }

        List<Flight> availableFlights = allFlights.stream()
            .filter(flight -> flight.getAvailableSeats() > 0)
            .sorted(Comparator.comparing(Flight::getPrice))
            .collect(Collectors.toList());

        logger.info("Found {} available flights from {} to {}",
            availableFlights.size(), departureCity, arrivalCity);

        return availableFlights;
    }

    @Transactional(readOnly = true)
    public Flight findByFlightNumber(String flightNumber) {
        Optional<Flight> flight = flightRepository.findByFlightNumber(flightNumber);
        if (flight.isEmpty()) {
            logger.warn("Flight not found with number: {}", flightNumber);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Flight not found with number: " + flightNumber);
        }
        logger.info("Found flight: {} from {} to {}",
            flightNumber, flight.get().getDepartureAirport(), flight.get().getArrivalAirport());
        return flight.get();
    }

    @Transactional(readOnly = true)
    public Flight getFlight(String id) {
        return flightRepository.findById(id)
            .orElseThrow(() -> {
                logger.warn("Flight not found with id: {}", id);
                return new ResponseStatusException(HttpStatus.NOT_FOUND, "Flight not found with id: " + id);
            });
    }

    @Transactional
    public Flight createFlight(Flight flight) {
        // Check if flight with same number already exists
        Optional<Flight> existingFlight = flightRepository.findByFlightNumber(flight.getFlightNumber());
        if (existingFlight.isPresent()) {
            logger.warn("Flight already exists with number: {}", flight.getFlightNumber());
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Flight already exists with number: " + flight.getFlightNumber());
        }

        // Validate airports exist
        validateAirportExists(flight.getDepartureAirport());
        validateAirportExists(flight.getArrivalAirport());

        Flight savedFlight = flightRepository.save(flight);
        logger.info("Created flight: {} from {} to {}",
            savedFlight.getFlightNumber(), savedFlight.getDepartureAirport(), savedFlight.getArrivalAirport());
        return savedFlight;
    }

    @Transactional
    public Flight updateFlight(String id, Flight flight) {
        Flight existingFlight = getFlight(id);

        // If flight number is being changed, check that new number doesn't conflict
        if (!existingFlight.getFlightNumber().equals(flight.getFlightNumber())) {
            Optional<Flight> conflictingFlight = flightRepository.findByFlightNumber(flight.getFlightNumber());
            if (conflictingFlight.isPresent()) {
                logger.warn("Cannot update flight: number {} already in use", flight.getFlightNumber());
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Flight number already in use: " + flight.getFlightNumber());
            }
        }

        // Validate airports exist if they're being changed
        if (!existingFlight.getDepartureAirport().equals(flight.getDepartureAirport())) {
            validateAirportExists(flight.getDepartureAirport());
        }

        if (!existingFlight.getArrivalAirport().equals(flight.getArrivalAirport())) {
            validateAirportExists(flight.getArrivalAirport());
        }

        // Preserve the ID
        flight.setId(id);

        Flight updatedFlight = flightRepository.save(flight);
        logger.info("Updated flight: {} from {} to {}",
            updatedFlight.getFlightNumber(), updatedFlight.getDepartureAirport(), updatedFlight.getArrivalAirport());
        return updatedFlight;
    }

    @Transactional
    public void deleteFlight(String id) {
        if (!flightRepository.existsById(id)) {
            logger.warn("Cannot delete: flight not found with id: {}", id);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Flight not found with id: " + id);
        }

        flightRepository.deleteById(id);
        logger.info("Deleted flight with id: {}", id);
    }

    @Transactional
    public Flight updateFlightStatus(String id, Flight.FlightStatus status) {
        Flight flight = getFlight(id);
        flight.setStatus(status);
        Flight updatedFlight = flightRepository.save(flight);
        logger.info("Updated flight status: {} to {}", flight.getFlightNumber(), status);
        return updatedFlight;
    }

    private void validateAirportExists(String airportCode) {
        if (!airportRepository.findByAirportCode(airportCode).isPresent()) {
            logger.warn("Airport not found with code: {}", airportCode);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Airport not found with code: " + airportCode);
        }
    }
}
