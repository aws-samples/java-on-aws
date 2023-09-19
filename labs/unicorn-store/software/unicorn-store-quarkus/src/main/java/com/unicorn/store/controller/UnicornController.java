package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.service.UnicornService;
import java.util.List;

import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("unicorns")
public class UnicornController {

  @Inject
  UnicornRepository unicornRepository;
  @Inject
  UnicornService unicornService;
  
  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  @Transactional
  public Unicorn createUnicorn(Unicorn unicorn) {
    return this.unicornRepository.persist(unicorn);
  }

  @GET
  @Produces(MediaType.APPLICATION_JSON)
  public List<Unicorn> getAllUnicorns() {
    return this.unicornRepository.findAll();
  }
  
  @GET
  @Path("{id}")
  @Produces(MediaType.APPLICATION_JSON)
  public Unicorn getUnicorn(@PathParam("id") String id) {
    return this.unicornRepository.findById(id);
  }
  
  @PUT
  @Path("{id}")
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  @Transactional
  public Unicorn updateUnicorn(@PathParam("id") String id, Unicorn unicorn) {
    unicorn.setId(id);
    return this.unicornRepository.merge(unicorn);
  }
  
  @DELETE
  @Path("{id}")
  @Produces(MediaType.APPLICATION_JSON)
  @Transactional
  public void deleteUnicorn(@PathParam("id") String id) {
    this.unicornRepository.removeById(id);
  }
}
