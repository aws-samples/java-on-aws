package com.example.travel.accommodations;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "hotels")
class Hotel {
    enum RoomType {
        STANDARD, DELUXE, SUITE, EXECUTIVE
    }

    enum HotelStatus {
        ACTIVE, INACTIVE, MAINTENANCE
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "hotel_name")
    @NotBlank(message = "Hotel name is required")
    @Size(max = 100, message = "Hotel name must not exceed 100 characters")
    private String hotelName;

    @Column(name = "hotel_chain")
    @Size(max = 100, message = "Hotel chain must not exceed 100 characters")
    private String hotelChain;

    @Column(name = "city")
    @NotBlank(message = "City is required")
    @Size(max = 100, message = "City must not exceed 100 characters")
    private String city;

    @Column(name = "country")
    @NotBlank(message = "Country is required")
    @Size(max = 100, message = "Country must not exceed 100 characters")
    private String country;

    @Column(name = "address")
    @Size(max = 255, message = "Address must not exceed 255 characters")
    private String address;

    @Column(name = "star_rating")
    @Min(value = 1, message = "Star rating must be at least 1")
    @Max(value = 5, message = "Star rating must not exceed 5")
    private Integer starRating;

    @Column(name = "price_per_night")
    @NotNull(message = "Price per night is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than zero")
    private BigDecimal pricePerNight;

    @Column(name = "currency")
    @NotBlank(message = "Currency is required")
    @Size(max = 3, message = "Currency code must not exceed 3 characters")
    private String currency;

    @Column(name = "available_rooms")
    @Min(value = 0, message = "Available rooms cannot be negative")
    private Integer availableRooms;

    @Column(name = "total_rooms")
    @Min(value = 1, message = "Total rooms must be at least 1")
    private Integer totalRooms;

    @Enumerated(EnumType.STRING)
    @Column(name = "room_type", length = 20)
    private RoomType roomType;

    @Column(name = "amenities", columnDefinition = "TEXT")
    private String amenities;

    @Column(name = "description", columnDefinition = "TEXT")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", length = 20)
    private HotelStatus status = HotelStatus.ACTIVE;

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    Hotel() {
    }

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        if (status == null) {
            status = HotelStatus.ACTIVE;
        }
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    public String getId() {
        return id;
    }

    public String getHotelName() {
        return hotelName;
    }

    public String getHotelChain() {
        return hotelChain;
    }

    public String getCity() {
        return city;
    }

    public String getCountry() {
        return country;
    }

    public String getAddress() {
        return address;
    }

    public Integer getStarRating() {
        return starRating;
    }

    public BigDecimal getPricePerNight() {
        return pricePerNight;
    }

    public String getCurrency() {
        return currency;
    }

    public Integer getAvailableRooms() {
        return availableRooms;
    }

    public Integer getTotalRooms() {
        return totalRooms;
    }

    public RoomType getRoomType() {
        return roomType;
    }

    public String getAmenities() {
        return amenities;
    }

    public String getDescription() {
        return description;
    }

    public HotelStatus getStatus() {
        return status;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setId(String id) {
        this.id = id;
    }

    public void setHotelName(String hotelName) {
        this.hotelName = hotelName;
    }

    public void setHotelChain(String hotelChain) {
        this.hotelChain = hotelChain;
    }

    public void setCity(String city) {
        this.city = city;
    }

    public void setCountry(String country) {
        this.country = country;
    }

    public void setAddress(String address) {
        this.address = address;
    }

    public void setStarRating(Integer starRating) {
        this.starRating = starRating;
    }

    public void setPricePerNight(BigDecimal pricePerNight) {
        this.pricePerNight = pricePerNight;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public void setAvailableRooms(Integer availableRooms) {
        this.availableRooms = availableRooms;
    }

    public void setTotalRooms(Integer totalRooms) {
        this.totalRooms = totalRooms;
    }

    public void setRoomType(RoomType roomType) {
        this.roomType = roomType;
    }

    public void setAmenities(String amenities) {
        this.amenities = amenities;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public void setStatus(HotelStatus status) {
        this.status = status;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
