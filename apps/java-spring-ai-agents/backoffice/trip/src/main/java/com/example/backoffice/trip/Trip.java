package com.example.backoffice.trip;

import com.example.backoffice.common.BackofficeConstants;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Objects;

@DynamoDbBean
public class Trip {

    public static final String TRIP_PREFIX = "TRIP#";
    public static final String REFERENCE_PREFIX = "TRP-";

    public enum TripStatus {
        PLANNED, APPROVED, COMPLETED, CANCELLED
    }

    private String pk;
    private String sk;
    private String tripReference;
    private String userId;
    private LocalDate departureDate;
    private LocalDate returnDate;
    private String origin;
    private String destination;
    private String purpose;
    private TripStatus status;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public Trip() {}

    public static Trip create(String userId, LocalDate departureDate, LocalDate returnDate,
                               String origin, String destination, String purpose) {
        Objects.requireNonNull(userId, "userId is required");
        Objects.requireNonNull(departureDate, "departureDate is required");
        Objects.requireNonNull(returnDate, "returnDate is required");
        Objects.requireNonNull(origin, "origin is required");
        Objects.requireNonNull(destination, "destination is required");

        if (returnDate.isBefore(departureDate)) {
            throw new IllegalArgumentException("returnDate must be after departureDate");
        }

        Trip trip = new Trip();
        String id = BackofficeConstants.generateId();
        trip.tripReference = REFERENCE_PREFIX + id;
        trip.userId = userId;
        trip.pk = BackofficeConstants.USER_PREFIX + userId;
        trip.sk = TRIP_PREFIX + trip.tripReference;
        trip.departureDate = departureDate;
        trip.returnDate = returnDate;
        trip.origin = origin;
        trip.destination = destination;
        trip.purpose = purpose;
        trip.status = TripStatus.PLANNED;
        trip.createdAt = LocalDateTime.now();
        trip.updatedAt = trip.createdAt;
        return trip;
    }

    @DynamoDbPartitionKey
    public String getPk() { return pk; }
    public void setPk(String pk) { this.pk = pk; }

    @DynamoDbSortKey
    public String getSk() { return sk; }
    public void setSk(String sk) { this.sk = sk; }

    @DynamoDbSecondaryPartitionKey(indexNames = "tripReference-index")
    public String getTripReference() { return tripReference; }
    public void setTripReference(String tripReference) { this.tripReference = tripReference; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public LocalDate getDepartureDate() { return departureDate; }
    public void setDepartureDate(LocalDate departureDate) { this.departureDate = departureDate; }

    public LocalDate getReturnDate() { return returnDate; }
    public void setReturnDate(LocalDate returnDate) { this.returnDate = returnDate; }

    public String getOrigin() { return origin; }
    public void setOrigin(String origin) { this.origin = origin; }

    public String getDestination() { return destination; }
    public void setDestination(String destination) { this.destination = destination; }

    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }

    public TripStatus getStatus() { return status; }
    public void setStatus(TripStatus status) { this.status = status; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Trip trip = (Trip) o;
        return Objects.equals(pk, trip.pk) && Objects.equals(sk, trip.sk);
    }

    @Override
    public int hashCode() {
        return Objects.hash(pk, sk);
    }

    @Override
    public String toString() {
        return "Trip{tripReference='%s', userId='%s', %s to %s, %s -> %s, status=%s}"
                .formatted(tripReference, userId, departureDate, returnDate, origin, destination, status);
    }
}
