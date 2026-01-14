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

    public Unicorn() {}

    public Unicorn(String name, String age, String size, String type) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Unicorn name is required and cannot be blank");
        }
        if (type == null || type.isBlank()) {
            throw new IllegalArgumentException("Unicorn type is required and cannot be blank");
        }
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

    public String getId() { return id; }
    public String getName() { return name; }
    public String getAge() { return age; }
    public String getSize() { return size; }
    public String getType() { return type; }

    public void setId(String id) { this.id = id; }
    public void setName(String name) { this.name = name; }
    public void setAge(String age) { this.age = age; }
    public void setSize(String size) { this.size = size; }
    public void setType(String type) { this.type = type; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Unicorn unicorn)) return false;
        return id != null && id.equals(unicorn.id);
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "Unicorn{id='%s', name='%s', age='%s', size='%s', type='%s'}"
            .formatted(id, name, age, size, type);
    }
}
