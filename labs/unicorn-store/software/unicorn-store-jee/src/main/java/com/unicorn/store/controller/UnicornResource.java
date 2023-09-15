package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.data.UnicornRepository;
import com.unicorn.store.service.UnicornService;
import java.net.URI;
import java.util.List;

import javax.inject.Inject;
import javax.transaction.Transactional;
import javax.ws.rs.BadRequestException;
import javax.ws.rs.Consumes;
import javax.ws.rs.GET;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.core.Context;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import javax.ws.rs.core.UriInfo;

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
