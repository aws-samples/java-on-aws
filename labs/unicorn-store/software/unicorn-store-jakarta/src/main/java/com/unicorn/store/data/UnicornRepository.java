package com.unicorn.store.data;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;

import com.unicorn.store.exceptions.ResourceNotFoundException;
import com.unicorn.store.model.Unicorn;
import java.util.UUID;

@ApplicationScoped
public class UnicornRepository {
    private final Logger logger = LoggerFactory.getLogger(getClass());

    @Inject
    EntityManager entityManager;

    public List<Unicorn> findAll() {
    return this.entityManager
        .createQuery("select x from unicorns x", Unicorn.class)
        .getResultList();
    }

    public Unicorn findById(String id) {
        Unicorn unicorn = this.entityManager.find(Unicorn.class, id);
        if (unicorn == null) {
            throw new ResourceNotFoundException();
        } else {
            return unicorn;
        }
    }

    public Unicorn insert(Unicorn unicorn) {
        if (unicorn.getId() == null) {
            unicorn.setId(UUID.randomUUID().toString());
        }
        this.entityManager.persist(unicorn);
        this.entityManager.flush();
        logger.info("Successfully created unicorn with ID: {}", unicorn.getId());
        return unicorn;
    }

    public Unicorn update(Unicorn unicorn, String unicornId) {
        unicorn.setId(unicornId);
        logger.info("Successfully updated unicorn with ID: {}", unicorn.getId());
        return this.entityManager.merge(unicorn);
    }

    public void delete(String id) {
        Unicorn unicorn = findById(id);
        if (unicorn != null) {
            this.entityManager.remove(unicorn);
            logger.info("Successfully deleted unicorn with ID: {}", unicorn.getId());
        } else {
            throw new ResourceNotFoundException();
        }
    }
}
