package com.unicorn.store.property;

import com.unicorn.store.model.Unicorn;
import net.jqwik.api.*;

import static org.assertj.core.api.Assertions.*;

// Property tests for Flexible Constructor Bodies (JEP 513) - validation before super()
class UnicornValidationPropertyTest {

    @Property(tries = 100)
    void validUnicornIsCreatedSuccessfully(
            @ForAll("validNames") String name,
            @ForAll("validAges") String age,
            @ForAll("validSizes") String size,
            @ForAll("validTypes") String type) {

        var unicorn = new Unicorn(name, age, size, type);

        assertThat(unicorn.getName()).isEqualTo(name);
        assertThat(unicorn.getAge()).isEqualTo(age);
        assertThat(unicorn.getSize()).isEqualTo(size);
        assertThat(unicorn.getType()).isEqualTo(type);
    }

    @Property(tries = 100)
    void nullNameIsRejected(
            @ForAll("validAges") String age,
            @ForAll("validSizes") String size,
            @ForAll("validTypes") String type) {

        assertThatThrownBy(() -> new Unicorn(null, age, size, type))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("name");
    }

    @Property(tries = 100)
    void blankNameIsRejected(
            @ForAll("blankStrings") String name,
            @ForAll("validAges") String age,
            @ForAll("validSizes") String size,
            @ForAll("validTypes") String type) {

        assertThatThrownBy(() -> new Unicorn(name, age, size, type))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("name");
    }

    @Property(tries = 100)
    void nullTypeIsRejected(
            @ForAll("validNames") String name,
            @ForAll("validAges") String age,
            @ForAll("validSizes") String size) {

        assertThatThrownBy(() -> new Unicorn(name, age, size, null))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("type");
    }

    @Property(tries = 100)
    void blankTypeIsRejected(
            @ForAll("validNames") String name,
            @ForAll("validAges") String age,
            @ForAll("validSizes") String size,
            @ForAll("blankStrings") String type) {

        assertThatThrownBy(() -> new Unicorn(name, age, size, type))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("type");
    }

    // --- Providers ---

    @Provide
    Arbitrary<String> validNames() {
        return Arbitraries.strings()
            .alpha()
            .ofMinLength(1)
            .ofMaxLength(50);
    }

    @Provide
    Arbitrary<String> validTypes() {
        return Arbitraries.of("EARTH", "WATER", "FIRE", "AIR", "COSMIC");
    }

    @Provide
    Arbitrary<String> validAges() {
        return Arbitraries.integers()
            .between(1, 1000)
            .map(String::valueOf);
    }

    @Provide
    Arbitrary<String> validSizes() {
        return Arbitraries.of("SMALL", "MEDIUM", "LARGE");
    }

    @Provide
    Arbitrary<String> blankStrings() {
        return Arbitraries.of("", "   ", "\t", "\n", "  \t\n  ");
    }
}
