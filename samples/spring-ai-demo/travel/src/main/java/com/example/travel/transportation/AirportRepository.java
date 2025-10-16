package com.example.travel.transportation;

import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
interface AirportRepository extends CrudRepository<Airport, String> {
    Optional<Airport> findByAirportCode(String airportCode);
    List<Airport> findByCityContainingIgnoreCase(String city);
    List<Airport> findByCountryContainingIgnoreCase(String country);
}
