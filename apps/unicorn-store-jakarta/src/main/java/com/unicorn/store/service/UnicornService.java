package com.unicorn.store.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.data.UnicornPublisher;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;

import java.util.List;
import java.util.ArrayList;


@ApplicationScoped
public class UnicornService {
    private final Logger logger = LoggerFactory.getLogger(getClass());

    @Inject
    UnicornRepository unicornRepository;
    @Inject
    UnicornPublisher unicornPublisher;

    public List<Unicorn> getAllUnicorns() {
        List<Unicorn> unicornList = new ArrayList<>();
        Iterable<Unicorn> iterator = unicornRepository.findAll();

        for (Unicorn unicorn : iterator){
            unicornList.add(unicorn);
        }
        return unicornList;
    }

    public Unicorn getUnicorn(String unicornId) {
        var unicorn = unicornRepository.findById(unicornId);
        return unicorn;
    }

    @Transactional
    public Unicorn createUnicorn(Unicorn unicorn) {
        var savedUnicorn = unicornRepository.insert(unicorn);
        publishEvent(savedUnicorn, UnicornEventType.UNICORN_CREATED);
        return savedUnicorn;
    }

    @Transactional
    public Unicorn updateUnicorn(Unicorn unicorn, String unicornId) {
        var savedUnicorn = unicornRepository.update(unicorn, unicornId);
        publishEvent(savedUnicorn, UnicornEventType.UNICORN_UPDATED);
        return savedUnicorn;
    }

    @Transactional
    public void deleteUnicorn(String unicornId) {
        Unicorn unicorn = unicornRepository.findById(unicornId);
        unicornRepository.delete(unicornId);
        publishEvent(unicorn, UnicornEventType.UNICORN_DELETED);
    }

    private void publishEvent(Unicorn unicorn, UnicornEventType type) {
        try {
            unicornPublisher.publish(unicorn, type);
        } catch (Exception e) {
            logger.error("Failed to publish {} event. Unicorn ID: {}. Error: {}",
                type, unicorn.getId(), e.getMessage());
            logger.debug("Stack trace:", e);
        }
    }
}
