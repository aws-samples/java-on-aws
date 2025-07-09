package com.example.travel.transportation;

import com.example.travel.common.ReferenceGenerator;
import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "flight_bookings")
class FlightBooking {
    enum BookingStatus {
        PENDING, CONFIRMED, CANCELLED, COMPLETED, REFUNDED
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "booking_reference", unique = true)
    @Size(max = 10, message = "Booking reference must not exceed 10 characters")
    private String bookingReference;

    @Column(name = "flight_id")
    @NotBlank(message = "Flight ID is required")
    private String flightId;

    @Column(name = "flight_date")
    @NotNull(message = "Flight date is required")
    private LocalDate flightDate;

    @Column(name = "customer_name")
    @NotBlank(message = "Customer name is required")
    @Size(max = 255, message = "Customer name must not exceed 255 characters")
    private String customerName;

    @Column(name = "customer_email")
    @NotBlank(message = "Customer email is required")
    @Email(message = "Invalid email format")
    @Size(max = 255, message = "Email must not exceed 255 characters")
    private String customerEmail;

    @Column(name = "number_of_passengers")
    @Min(value = 1, message = "Number of passengers must be at least 1")
    @Max(value = 9, message = "Number of passengers cannot exceed 9")
    private Integer numberOfPassengers = 1;

    @Column(name = "total_price")
    private BigDecimal totalPrice;

    @Column(name = "currency")
    @Size(max = 3, message = "Currency code must not exceed 3 characters")
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status")
    private BookingStatus status = BookingStatus.PENDING;

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    FlightBooking() {
    }

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }
        if (bookingReference == null || bookingReference.trim().isEmpty()) {
            bookingReference = ReferenceGenerator.generateWithPrefix("FLT", 6);
        }
        if (status == null) {
            status = BookingStatus.PENDING;
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

    public String getBookingReference() {
        return bookingReference;
    }

    public String getFlightId() {
        return flightId;
    }

    public LocalDate getFlightDate() {
        return flightDate;
    }

    public String getCustomerName() {
        return customerName;
    }

    public String getCustomerEmail() {
        return customerEmail;
    }

    public Integer getNumberOfPassengers() {
        return numberOfPassengers;
    }

    public BigDecimal getTotalPrice() {
        return totalPrice;
    }

    public String getCurrency() {
        return currency;
    }

    public BookingStatus getStatus() {
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

    public void setBookingReference(String bookingReference) {
        this.bookingReference = bookingReference;
    }

    public void setFlightId(String flightId) {
        this.flightId = flightId;
    }

    public void setFlightDate(LocalDate flightDate) {
        this.flightDate = flightDate;
    }

    public void setCustomerName(String customerName) {
        this.customerName = customerName;
    }

    public void setCustomerEmail(String customerEmail) {
        this.customerEmail = customerEmail;
    }

    public void setNumberOfPassengers(Integer numberOfPassengers) {
        this.numberOfPassengers = numberOfPassengers;
    }

    public void setTotalPrice(BigDecimal totalPrice) {
        this.totalPrice = totalPrice;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public void setStatus(BookingStatus status) {
        this.status = status;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
