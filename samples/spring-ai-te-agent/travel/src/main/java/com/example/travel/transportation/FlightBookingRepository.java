package com.example.travel.transportation;

import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
interface FlightBookingRepository extends CrudRepository<FlightBooking, String> {
    Optional<FlightBooking> findByBookingReference(String bookingReference);
    List<FlightBooking> findByFlightId(String flightId);
}
