package com.unicorn.store.data;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;

@ApplicationScoped
public class EntityManagerProducer {

  @PersistenceContext
//   @Produces
  EntityManager entityManager;
}
