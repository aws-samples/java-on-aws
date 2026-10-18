package com.example.backoffice.trip;

import com.example.backoffice.common.BackofficeConstants;
import com.example.backoffice.exception.InvalidOperationException;
import com.example.backoffice.exception.ResourceNotFoundException;
import io.awspring.cloud.dynamodb.DynamoDbTemplate;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.model.QueryConditional;
import software.amazon.awssdk.enhanced.dynamodb.model.QueryEnhancedRequest;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
public class TripService {

    private final DynamoDbTemplate dynamoDbTemplate;

    public TripService(DynamoDbTemplate dynamoDbTemplate) {
        this.dynamoDbTemplate = dynamoDbTemplate;
    }

    public Trip registerTrip(String userId, LocalDate departureDate, LocalDate returnDate,
                             String origin, String destination, String purpose) {
        Trip trip = Trip.create(userId, departureDate, returnDate, origin, destination, purpose);
        return dynamoDbTemplate.save(trip);
    }

    public List<Trip> getTrips(String userId) {
        QueryEnhancedRequest request = QueryEnhancedRequest.builder()
                .queryConditional(QueryConditional.keyEqualTo(
                        Key.builder().partitionValue(BackofficeConstants.USER_PREFIX + userId).build()))
                .build();
        return dynamoDbTemplate.query(request, Trip.class).items().stream().toList();
    }

    public Trip getTrip(String tripReference) {
        QueryEnhancedRequest request = QueryEnhancedRequest.builder()
                .queryConditional(QueryConditional.keyEqualTo(
                        Key.builder().partitionValue(tripReference).build()))
                .build();
        return dynamoDbTemplate.query(request, Trip.class, "tripReference-index")
                .items().stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Trip", tripReference));
    }

    public Trip cancelTrip(String tripReference) {
        Trip trip = getTrip(tripReference);
        if (trip.getStatus() == Trip.TripStatus.COMPLETED) {
            throw new InvalidOperationException("Cannot cancel completed trip");
        }
        trip.setStatus(Trip.TripStatus.CANCELLED);
        trip.setUpdatedAt(LocalDateTime.now());
        return dynamoDbTemplate.save(trip);
    }
}
