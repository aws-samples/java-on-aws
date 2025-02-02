package com.unicorn.store.service;

import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.data.UnicornPublisher;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;

import javax.enterprise.context.ApplicationScoped;
import javax.inject.Inject;
import javax.transaction.Transactional;

import java.util.List;
import java.util.ArrayList;


@ApplicationScoped
public class UnicornService {

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
        Unicorn unicorn = unicornRepository.findById(unicornId);
        return unicorn;
    }

    @Transactional
    public Unicorn createUnicorn(Unicorn unicorn) {
        Unicorn savedUnicorn = unicornRepository.insert(unicorn);
        unicornPublisher.publish(savedUnicorn, UnicornEventType.UNICORN_CREATED);
        return savedUnicorn;
    }

    @Transactional
    public Unicorn updateUnicorn(Unicorn unicorn, String unicornId) {
        Unicorn savedUnicorn = unicornRepository.update(unicorn, unicornId);
        unicornPublisher.publish(savedUnicorn, UnicornEventType.UNICORN_UPDATED);
        return savedUnicorn;
    }

    @Transactional
    public void deleteUnicorn(String unicornId) {
        Unicorn unicorn = unicornRepository.findById(unicornId);
        unicornRepository.delete(unicornId);
        unicornPublisher.publish(unicorn, UnicornEventType.UNICORN_DELETED);
    }
}
