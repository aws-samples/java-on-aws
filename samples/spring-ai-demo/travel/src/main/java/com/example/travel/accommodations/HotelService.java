package com.example.travel.accommodations;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
public class HotelService {
    private static final Logger logger = LoggerFactory.getLogger(HotelService.class);
    private final HotelRepository hotelRepository;

    HotelService(HotelRepository hotelRepository) {
        this.hotelRepository = hotelRepository;
    }

    /**
     * Find hotels in a city for specific dates
     */
    @Transactional(readOnly = true)
    public List<Hotel> findHotelsByCity(String city, LocalDate checkInDate, Integer numberOfNights) {
        List<Hotel> hotels = hotelRepository.findByCityContainingIgnoreCaseAndStatus(
            city, Hotel.HotelStatus.ACTIVE);

        List<Hotel> availableHotels = hotels.stream()
            .filter(hotel -> hotel.getAvailableRooms() > 0)
            .sorted(Comparator.comparing(Hotel::getPricePerNight))
            .collect(Collectors.toList());

        logger.info("Found {} available hotels in {} for check-in on {}",
            availableHotels.size(), city, checkInDate);

        return availableHotels;
    }

    /**
     * Get hotel by ID
     */
    @Transactional(readOnly = true)
    public Hotel getHotel(String id) {
        Optional<Hotel> hotel = hotelRepository.findById(id);
        if (hotel.isEmpty()) {
            logger.warn("Hotel not found with ID: {}", id);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Hotel not found with ID: " + id);
        }

        logger.info("Found hotel: {}, city: {}, available rooms: {}",
            hotel.get().getHotelName(), hotel.get().getCity(), hotel.get().getAvailableRooms());

        return hotel.get();
    }

    /**
     * Find hotels by name
     */
    @Transactional(readOnly = true)
    public List<Hotel> findHotelsByName(String hotelName) {
        List<Hotel> hotels = hotelRepository.findByHotelNameContainingIgnoreCase(hotelName);

        if (hotels.isEmpty()) {
            logger.warn("No hotels found with name containing: {}", hotelName);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No hotels found with name containing: " + hotelName);
        }

        logger.info("Found {} hotels with name containing: {}", hotels.size(), hotelName);

        return hotels;
    }

    /**
     * Create a new hotel
     */
    @Transactional
    public Hotel createHotel(Hotel hotel) {
        // Validate hotel data
        validateHotelData(hotel);

        // Save the hotel
        Hotel savedHotel = hotelRepository.save(hotel);

        logger.info("Created hotel: {}, city: {}, rooms: {}/{}",
            savedHotel.getHotelName(), savedHotel.getCity(),
            savedHotel.getAvailableRooms(), savedHotel.getTotalRooms());

        return savedHotel;
    }

    /**
     * Update an existing hotel
     */
    @Transactional
    public Hotel updateHotel(String id, Hotel hotel) {
        // Check if hotel exists
        Hotel existingHotel = getHotel(id);

        // Validate hotel data
        validateHotelData(hotel);

        // Preserve the ID
        hotel.setId(id);

        // Save the updated hotel
        Hotel updatedHotel = hotelRepository.save(hotel);

        logger.info("Updated hotel: {}, city: {}, rooms: {}/{}",
            updatedHotel.getHotelName(), updatedHotel.getCity(),
            updatedHotel.getAvailableRooms(), updatedHotel.getTotalRooms());

        return updatedHotel;
    }

    /**
     * Delete a hotel
     */
    @Transactional
    public void deleteHotel(String id) {
        // Check if hotel exists
        if (!hotelRepository.existsById(id)) {
            logger.warn("Cannot delete: hotel not found with id: {}", id);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Hotel not found with id: " + id);
        }

        // Delete the hotel
        hotelRepository.deleteById(id);

        logger.info("Deleted hotel with id: {}", id);
    }

    /**
     * Update hotel status
     */
    @Transactional
    public Hotel updateHotelStatus(String id, Hotel.HotelStatus status) {
        Hotel hotel = getHotel(id);
        hotel.setStatus(status);

        Hotel updatedHotel = hotelRepository.save(hotel);

        logger.info("Updated hotel status: {} to {}",
            hotel.getHotelName(), status);

        return updatedHotel;
    }

    /**
     * Validate hotel data
     */
    private void validateHotelData(Hotel hotel) {
        // Check that total rooms is not less than available rooms
        if (hotel.getTotalRooms() < hotel.getAvailableRooms()) {
            logger.warn("Invalid hotel data: total rooms ({}) less than available rooms ({})",
                hotel.getTotalRooms(), hotel.getAvailableRooms());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Total rooms cannot be less than available rooms");
        }

        // Check that price is positive
        if (hotel.getPricePerNight() != null && hotel.getPricePerNight().signum() <= 0) {
            logger.warn("Invalid hotel data: price per night must be positive");
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Price per night must be positive");
        }
    }
}
