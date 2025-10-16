package com.example.travel.accommodations;

import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;
import java.util.Optional;

@Repository
interface HotelBookingRepository extends CrudRepository<HotelBooking, String> {
    Optional<HotelBooking> findByBookingReference(String bookingReference);
}
