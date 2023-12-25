package com.unicorn.store.data;

import javax.enterprise.context.ApplicationScoped;
import javax.enterprise.inject.Produces;
import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;

@ApplicationScoped
public class EntityManagerProducer {

    @PersistenceContext(unitName = "unicorns")
    private EntityManager entityManager;

    @Produces
    public EntityManager entityManager(){
      return entityManager;
    }
}
