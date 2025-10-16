package com.example.travel.accommodations;

import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
interface HotelRepository extends CrudRepository<Hotel, String> {
    List<Hotel> findByCityContainingIgnoreCaseAndStatus(String city, Hotel.HotelStatus status);
    List<Hotel> findByHotelNameContainingIgnoreCase(String hotelName);
}
