package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.service.UnicornService;
import java.net.URI;
import java.util.List;

import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;

@Path("unicorns")
public class UnicornResource {

  @Inject
  UnicornRepository unicornRepository;

  @GET
  @Produces(MediaType.APPLICATION_JSON)
  public List<Unicorn> get() {
    return this.unicornRepository.findAll();
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Transactional
  public Response post(Unicorn unicorn, @Context UriInfo uriInfo) {
    if (unicorn.getId() != null) {
      throw new BadRequestException("Id must not be set");
    }

    this.unicornRepository.persist(unicorn);

    URI uri = uriInfo
        .getAbsolutePathBuilder()
        .path(unicorn.getId().toString())
        .build();
    return Response
        .created(uri)
        .build();
  }

  @Inject
  UnicornService unicornService;

//   @Path("averageAge")
//   @GET
//   @Produces(MediaType.APPLICATION_JSON)
//   public double getAverageAge() {
//     return this.unicornService.getAverageAge();
//   }
}
