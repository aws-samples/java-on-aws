package com.unicorn.store.data;

import java.util.List;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;

import io.quarkus.hibernate.orm.panache.PanacheRepository;

import com.unicorn.store.exceptions.ResourceNotFoundException;
import com.unicorn.store.model.Unicorn;

@ApplicationScoped
public class UnicornRepository implements PanacheRepository<Unicorn> {
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
        this.entityManager.persist(unicorn);
        this.entityManager.flush();
        return unicorn;
    }

    public Unicorn update(Unicorn unicorn, String unicornId) {
        unicorn.setId(unicornId);
        return this.entityManager.merge(unicorn);
    }

    public void delete(String id) {
        Unicorn unicorn = findById(id);
        if (unicorn != null) {
            this.entityManager.remove(unicorn);
        } else {
            throw new ResourceNotFoundException();
        }
    }
}
