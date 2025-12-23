package com.unicorn.store.service;

import com.unicorn.store.data.UnicornPublisher;
import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.exceptions.ResourceNotFoundException;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.UUID;
import java.util.List;
import java.util.stream.StreamSupport;

@Service
public class UnicornService {
    private final UnicornRepository unicornRepository;
    private final UnicornPublisher unicornPublisher;
    private static final Logger logger = LoggerFactory.getLogger(UnicornService.class);

    public UnicornService(UnicornRepository unicornRepository, UnicornPublisher unicornPublisher) {
        this.unicornRepository = unicornRepository;
        this.unicornPublisher = unicornPublisher;
    }

    @Transactional
    public Unicorn createUnicorn(Unicorn unicorn) {
        logger.debug("Creating unicorn: {}", unicorn);
        
        var unicornWithId = unicorn.id() == null 
            ? unicorn.withId(UUID.randomUUID().toString())
            : unicorn;
            
        validateUnicorn(unicornWithId);
        var savedUnicorn = unicornRepository.save(unicornWithId);
        publishUnicornEvent(savedUnicorn, UnicornEventType.UNICORN_CREATED);

        logger.debug("Created unicorn with ID: {}", savedUnicorn.id());
        return savedUnicorn;
    }

    public List<Unicorn> getAllUnicorns() {
        logger.debug("Retrieving all unicorns");
        return StreamSupport.stream(unicornRepository.findAll().spliterator(), false).toList();
    }

    @Transactional
    public List<Unicorn> createUnicorns(List<Unicorn> unicorns) {
        return unicorns.stream()
                .map(this::createUnicorn)
                .toList();
    }

    @Transactional
    public Unicorn updateUnicorn(Unicorn unicorn, String unicornId) {
        logger.debug("Updating unicorn with ID: {}", unicornId);
        validateUnicorn(unicorn);

        // Verify existence
        getUnicorn(unicornId);

        var updatedUnicorn = unicorn.withId(unicornId);
        var savedUnicorn = unicornRepository.save(updatedUnicorn);
        publishUnicornEvent(savedUnicorn, UnicornEventType.UNICORN_UPDATED);

        logger.debug("Updated unicorn with ID: {}", unicornId);
        return savedUnicorn;
    }

    public Unicorn getUnicorn(String unicornId) {
        logger.debug("Retrieving unicorn with ID: {}", unicornId);
        return unicornRepository.findById(unicornId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Unicorn not found with ID: " + unicornId));
    }

    @Transactional
    public void deleteUnicorn(String unicornId) {
        logger.debug("Deleting unicorn with ID: {}", unicornId);
        var unicorn = getUnicorn(unicornId);

        unicornRepository.delete(unicorn);
        publishUnicornEvent(unicorn, UnicornEventType.UNICORN_DELETED);

        logger.debug("Deleted unicorn with ID: {}", unicornId);
    }

    private void validateUnicorn(Unicorn unicorn) {
        switch (unicorn) {
            case null -> throw new IllegalArgumentException("Unicorn cannot be null");
            case Unicorn u when u.name() == null || u.name().isBlank() -> 
                throw new IllegalArgumentException("Unicorn name cannot be null or blank");
            case Unicorn u when u.type() == null || u.type().isBlank() -> 
                throw new IllegalArgumentException("Unicorn type cannot be null or blank");
            default -> { /* Valid unicorn */ }
        }
    }

    private void publishUnicornEvent(Unicorn unicorn, UnicornEventType eventType) {
        try {
            unicornPublisher.publish(unicorn, eventType).get();
        } catch (Exception e) {
            logger.error("Failed to publish {} event for unicorn ID: {}",
                    eventType, unicorn.id(), e);
        }
    }
}