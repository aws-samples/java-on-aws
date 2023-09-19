package com.unicorn.store.data;

import java.util.List;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;

import com.unicorn.store.model.Unicorn;

@ApplicationScoped
public class UnicornRepository {
  @Inject
  EntityManager entityManager;

  public Unicorn persist(Unicorn unicorn) {
    this.entityManager.persist(unicorn);
    this.entityManager.flush();
    return unicorn;
  }

  public Unicorn merge(Unicorn unicorn) {
    return this.entityManager.merge(unicorn);
  }
  
  public void removeById(String id) {
    Unicorn unicorn = findById(id);
    if (unicorn != null)
      this.entityManager.remove(unicorn);
  }

  public Unicorn findById(String id) {
    return this.entityManager.find(Unicorn.class, id);
  }

  public List<Unicorn> findAll() {
    return this.entityManager
      .createQuery("select x from unicorns x", Unicorn.class)
      .getResultList();
  }
}
