package com.example.travel.transportation;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.UUID;

@Entity
@Table(name = "flights")
class Flight {

    // Java enums for type safety
    enum FlightStatus {
        SCHEDULED, BOARDING, DEPARTED, IN_FLIGHT, ARRIVED, DELAYED, CANCELLED
    }

    enum AircraftType {
        BOEING_737, BOEING_747, BOEING_777, BOEING_787, BOEING_767,
        AIRBUS_A320, AIRBUS_A330, AIRBUS_A350, AIRBUS_A380,
        EMBRAER_E190, BOMBARDIER_CRJ
    }

    enum SeatClass {
        ECONOMY, PREMIUM_ECONOMY, BUSINESS, FIRST
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "flight_number", length = 10, unique = true)
    @NotBlank(message = "Flight number is required")
    @Pattern(regexp = "^[A-Z]{2}\\d{3,4}$", message = "Flight number must be in format like AA1234")
    private String flightNumber;

    @Column(name = "airline_name")
    @NotBlank(message = "Airline name is required")
    @Size(max = 100, message = "Airline name must not exceed 100 characters")
    private String airlineName;

    @Column(name = "departure_airport")
    @NotBlank(message = "Departure airport is required")
    @Pattern(regexp = "^[A-Z]{3}$", message = "Airport code must be 3 uppercase letters")
    private String departureAirport;

    @Column(name = "arrival_airport")
    @NotBlank(message = "Arrival airport is required")
    @Pattern(regexp = "^[A-Z]{3}$", message = "Airport code must be 3 uppercase letters")
    private String arrivalAirport;

    @Column(name = "departure_time")
    @NotNull(message = "Departure time is required")
    private LocalTime departureTime;

    @Column(name = "arrival_time")
    @NotNull(message = "Arrival time is required")
    private LocalTime arrivalTime;

    @Column(name = "duration_minutes")
    @Min(value = 30, message = "Flight duration must be at least 30 minutes")
    private Integer durationMinutes;

    @Column(name = "price")
    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than zero")
    private BigDecimal price;

    @Column(name = "currency")
    @NotBlank(message = "Currency is required")
    @Pattern(regexp = "USD|EUR|GBP|CAD|JPY|AUD|CHF|CNY|INR|BRL|MXN|KRW|SGD|HKD|NOK|SEK|DKK|PLN|CZK|HUF|RUB|TRY|ZAR|NZD|THB|MYR|PHP|IDR|VND",
             message = "Currency must be a valid ISO currency code")
    private String currency;

    @Column(name = "available_seats")
    @Min(value = 0, message = "Available seats cannot be negative")
    private Integer availableSeats;

    @Column(name = "total_seats")
    @Min(value = 1, message = "Total seats must be at least 1")
    private Integer totalSeats;

    // Store as String in database, use enum in Java
    @Enumerated(EnumType.STRING)
    @Column(name = "aircraft_type", length = 20)
    private AircraftType aircraftType;

    // Store as String in database, use enum in Java
    @Enumerated(EnumType.STRING)
    @Column(name = "seat_class", length = 20)
    private SeatClass seatClass = SeatClass.ECONOMY;

    // Store as String in database, use enum in Java
    @Enumerated(EnumType.STRING)
    @Column(name = "status", length = 20)
    private FlightStatus status = FlightStatus.SCHEDULED;

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    // Default constructor
    Flight() {
    }

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
        if (durationMinutes == null) {
            durationMinutes = calculateDuration();
        }
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
        if (durationMinutes == null) {
            durationMinutes = calculateDuration();
        }
    }

    private Integer calculateDuration() {
        if (departureTime != null && arrivalTime != null) {
            // Calculate duration considering potential next-day arrival
            int depMinutes = departureTime.getHour() * 60 + departureTime.getMinute();
            int arrMinutes = arrivalTime.getHour() * 60 + arrivalTime.getMinute();

            if (arrMinutes >= depMinutes) {
                return arrMinutes - depMinutes;
            } else {
                // Next day arrival
                return (24 * 60) - depMinutes + arrMinutes;
            }
        }
        return null;
    }

    // Getters
    public String getId() {
        return id;
    }

    public String getFlightNumber() {
        return flightNumber;
    }

    public String getAirlineName() {
        return airlineName;
    }

    public String getDepartureAirport() {
        return departureAirport;
    }

    public String getArrivalAirport() {
        return arrivalAirport;
    }

    public LocalTime getDepartureTime() {
        return departureTime;
    }

    public LocalTime getArrivalTime() {
        return arrivalTime;
    }

    public Integer getDurationMinutes() {
        return durationMinutes;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public String getCurrency() {
        return currency;
    }

    public Integer getAvailableSeats() {
        return availableSeats;
    }

    public Integer getTotalSeats() {
        return totalSeats;
    }

    public AircraftType getAircraftType() {
        return aircraftType;
    }

    public SeatClass getSeatClass() {
        return seatClass;
    }

    public FlightStatus getStatus() {
        return status;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    // Setters
    public void setId(String id) {
        this.id = id;
    }

    public void setFlightNumber(String flightNumber) {
        this.flightNumber = flightNumber;
    }

    public void setAirlineName(String airlineName) {
        this.airlineName = airlineName;
    }

    public void setDepartureAirport(String departureAirport) {
        this.departureAirport = departureAirport;
    }

    public void setArrivalAirport(String arrivalAirport) {
        this.arrivalAirport = arrivalAirport;
    }

    public void setDepartureTime(LocalTime departureTime) {
        this.departureTime = departureTime;
    }

    public void setArrivalTime(LocalTime arrivalTime) {
        this.arrivalTime = arrivalTime;
    }

    public void setDurationMinutes(Integer durationMinutes) {
        this.durationMinutes = durationMinutes;
    }

    public void setPrice(BigDecimal price) {
        this.price = price;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public void setAvailableSeats(Integer availableSeats) {
        this.availableSeats = availableSeats;
    }

    public void setTotalSeats(Integer totalSeats) {
        this.totalSeats = totalSeats;
    }

    public void setAircraftType(AircraftType aircraftType) {
        this.aircraftType = aircraftType;
    }

    public void setSeatClass(SeatClass seatClass) {
        this.seatClass = seatClass;
    }

    public void setStatus(FlightStatus status) {
        this.status = status;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
