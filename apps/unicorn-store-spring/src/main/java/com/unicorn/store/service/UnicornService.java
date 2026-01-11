package com.unicorn.store.service;

import com.unicorn.store.context.RequestContext;
import com.unicorn.store.data.UnicornPublisher;
import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.exceptions.ResourceNotFoundException;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;
import io.micrometer.observation.annotation.Observed;
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

    @Observed(name = "unicorn.create")
    @Transactional
    public Unicorn createUnicorn(Unicorn unicorn) {
        // Access request ID from Scoped Value (JEP 506) - no parameter passing needed
        String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
        logger.debug("[{}] Creating unicorn: {}", requestId, unicorn);

        var unicornWithId = unicorn.getId() == null
            ? unicorn.withId(UUID.randomUUID().toString())
            : unicorn;

        validateUnicorn(unicornWithId);
        var savedUnicorn = unicornRepository.save(unicornWithId);
        publishUnicornEvent(savedUnicorn, UnicornEventType.UNICORN_CREATED);

        logger.info("[{}] Created unicorn with ID: {}", requestId, savedUnicorn.getId());
        return savedUnicorn;
    }

    // Java 21 Sequenced Collections: getFirst()/getLast()
    public List<Unicorn> getAllUnicorns() {
        String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
        logger.debug("[{}] Retrieving all unicorns", requestId);

        List<Unicorn> unicorns = StreamSupport
            .stream(unicornRepository.findAll().spliterator(), false)
            .toList();

        if (!unicorns.isEmpty()) {
            logger.debug("[{}] First unicorn: {}, Last unicorn: {}",
                requestId, unicorns.getFirst().getName(), unicorns.getLast().getName());
        }

        return unicorns;
    }

    @Transactional
    public List<Unicorn> createUnicorns(List<Unicorn> unicorns) {
        return unicorns.stream()
                .map(this::createUnicorn)
                .toList();
    }

    @Observed(name = "unicorn.update")
    @Transactional
    public Unicorn updateUnicorn(Unicorn unicorn, String unicornId) {
        String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
        logger.debug("[{}] Updating unicorn with ID: {}", requestId, unicornId);
        validateUnicorn(unicorn);

        // Verify existence
        getUnicorn(unicornId);

        var updatedUnicorn = unicorn.withId(unicornId);
        var savedUnicorn = unicornRepository.save(updatedUnicorn);
        publishUnicornEvent(savedUnicorn, UnicornEventType.UNICORN_UPDATED);

        logger.info("[{}] Updated unicorn with ID: {}", requestId, unicornId);
        return savedUnicorn;
    }

    @Observed(name = "unicorn.get")
    public Unicorn getUnicorn(String unicornId) {
        String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
        logger.debug("[{}] Retrieving unicorn with ID: {}", requestId, unicornId);
        return unicornRepository.findById(unicornId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Unicorn not found with ID: " + unicornId));
    }

    @Observed(name = "unicorn.delete")
    @Transactional
    public void deleteUnicorn(String unicornId) {
        String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
        logger.debug("[{}] Deleting unicorn with ID: {}", requestId, unicornId);
        var unicorn = getUnicorn(unicornId);

        unicornRepository.delete(unicorn);
        publishUnicornEvent(unicorn, UnicornEventType.UNICORN_DELETED);

        logger.info("[{}] Deleted unicorn with ID: {}", requestId, unicornId);
    }

    // Java 21 Pattern Matching with guarded patterns (case X when condition)
    private void validateUnicorn(Unicorn unicorn) {
        switch (unicorn) {
            case null -> throw new IllegalArgumentException("Unicorn cannot be null");
            case Unicorn u when u.getName() == null || u.getName().isBlank() ->
                throw new IllegalArgumentException("Unicorn name cannot be null or blank");
            case Unicorn u when u.getType() == null || u.getType().isBlank() ->
                throw new IllegalArgumentException("Unicorn type cannot be null or blank");
            default -> { /* Valid unicorn */ }
        }
    }

    private void publishUnicornEvent(Unicorn unicorn, UnicornEventType eventType) {
        try {
            unicornPublisher.publish(unicorn, eventType).get();
        } catch (InterruptedException _) {
            // Java 22 unnamed variable (_)
            Thread.currentThread().interrupt();
            String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
            logger.warn("[{}] Event publishing interrupted for unicorn ID: {}",
                requestId, unicorn.getId());
        } catch (Exception e) {
            String requestId = RequestContext.REQUEST_ID.orElse("no-request-id");
            logger.error("[{}] Failed to publish {} event for unicorn ID: {}",
                    requestId, eventType, unicorn.getId(), e);
        }
    }
}