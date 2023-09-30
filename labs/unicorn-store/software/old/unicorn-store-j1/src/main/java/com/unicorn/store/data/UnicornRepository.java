package com.unicorn.store.data;

import java.util.List;
import java.util.UUID;

import javax.enterprise.context.ApplicationScoped;
import javax.inject.Inject;
import javax.persistence.EntityManager;

import com.unicorn.store.model.Unicorn;

@ApplicationScoped
public class UnicornRepository {
  @Inject
  EntityManager entityManager;

  public void persist(Unicorn unicorn) {
    this.entityManager.persist(unicorn);
  }

  public Unicorn merge(Unicorn unicorn) {
    return this.entityManager.merge(unicorn);
  }

  public void removeById(UUID id) {
    Unicorn unicorn = findById(id);
    if (unicorn != null)
      this.entityManager.remove(unicorn);
  }

  public Unicorn findById(UUID id) {
    return this.entityManager.find(Unicorn.class, id);
  }

  public List<Unicorn> findAll() {
    return this.entityManager
      .createQuery("select x from unicorns x", Unicorn.class)
      .getResultList();
  }
}
