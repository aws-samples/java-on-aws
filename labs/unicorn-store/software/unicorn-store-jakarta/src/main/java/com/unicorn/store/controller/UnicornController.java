package com.unicorn.store.controller;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;

import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

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
