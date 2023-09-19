package com.unicorn.store.service;

import com.unicorn.store.data.UnicornRepository;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
public class UnicornService {

  @Inject
  UnicornRepository unicornRepository;
}
