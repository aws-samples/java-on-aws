package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;
import java.util.List;

import javax.inject.Inject;
import javax.ws.rs.Consumes;
import javax.ws.rs.POST;
import javax.ws.rs.GET;
import javax.ws.rs.PUT;
import javax.ws.rs.DELETE;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

@Path("unicorns")
public class UnicornController {
    @Inject
    UnicornService unicornService;

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public String getAllUnicorns() {
        Gson gson = new GsonBuilder().setPrettyPrinting().create();
        String jsonOutput = gson.toJson(this.unicornService.getAllUnicorns());
        return jsonOutput;
    }

    @GET
    @Path("{id}")
    @Produces(MediaType.APPLICATION_JSON)
    public Unicorn getUnicorn(@PathParam("id") String id) {
        return this.unicornService.getUnicorn(id);
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Unicorn createUnicorn(Unicorn unicorn) {
        return this.unicornService.createUnicorn(unicorn);
    }

    @PUT
    @Path("{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Unicorn updateUnicorn(@PathParam("id") String id, Unicorn unicorn) {
    unicorn.setId(id);
        return this.unicornService.updateUnicorn(unicorn, id);
    }

    @DELETE
    @Path("{id}")
    @Produces(MediaType.APPLICATION_JSON)
    public void deleteUnicorn(@PathParam("id") String id) {
        this.unicornService.deleteUnicorn(id);
    }
}
