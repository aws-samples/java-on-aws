package com.unicorn.store.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import com.fasterxml.jackson.annotation.JsonProperty;

@Entity(name = "unicorns")
public class Unicorn {

    @Id
    @JsonProperty("id")
    private String id;
    
    @JsonProperty("name")
    private String name;
    
    @JsonProperty("age")
    private String age;
    
    @JsonProperty("size")
    private String size;
    
    @JsonProperty("type")
    private String type;

    public Unicorn() {
    }

    public Unicorn(String name, String age, String size, String type) {
        this.name = name;
        this.age = age;
        this.size = size;
        this.type = type;
    }

    public Unicorn withId(String newId) {
        var unicorn = new Unicorn(name, age, size, type);
        unicorn.id = newId;
        return unicorn;
    }

    // Record-style accessors
    public String id() { return id; }
    public String name() { return name; }
    public String age() { return age; }
    public String size() { return size; }
    public String type() { return type; }

    // Traditional getters for Jackson
    public String getId() { return id; }
    public String getName() { return name; }
    public String getAge() { return age; }
    public String getSize() { return size; }
    public String getType() { return type; }

    // Setters for JPA and Jackson
    public void setId(String id) { this.id = id; }
    public void setName(String name) { this.name = name; }
    public void setAge(String age) { this.age = age; }
    public void setSize(String size) { this.size = size; }
    public void setType(String type) { this.type = type; }
}