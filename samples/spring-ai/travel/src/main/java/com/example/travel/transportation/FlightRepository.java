package com.example.travel.transportation;

import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
interface FlightRepository extends CrudRepository<Flight, String> {
    Optional<Flight> findByFlightNumber(String flightNumber);
    List<Flight> findByDepartureAirportAndArrivalAirportAndStatus(
        String departureAirport,
        String arrivalAirport,
        Flight.FlightStatus status
    );
}
