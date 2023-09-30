package com.unicorn.store.service;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.data.UnicornRepository;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
public class UnicornService {

  @Inject
  UnicornRepository unicornRepository;

//   public double getAverageAge() {
//     double totalAge = 0;
//     int count = 0;
//     for (Unicorn unicorn : this.unicornRepository.findAll()) {
//       ++count;
//       totalAge += unicorn.getAge();
//     }
//     return count != 0 ? (totalAge / count) : 0;
//   }
}
