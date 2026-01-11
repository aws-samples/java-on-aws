package com.unicorn.store.property;

import com.unicorn.store.model.Unicorn;
import net.jqwik.api.*;

import java.util.UUID;

import static org.assertj.core.api.Assertions.*;

// Property tests for Unicorn equals/hashCode contract (JPA entity pattern)
class UnicornEqualsPropertyTest {

    @Property(tries = 100)
    void reflexivity(@ForAll("unicorns") Unicorn unicorn) {
        // x.equals(x) must be true
        assertThat(unicorn).isEqualTo(unicorn);
    }

    @Property(tries = 100)
    void symmetry(@ForAll("unicornsWithId") Unicorn a) {
        // Create another unicorn with same ID
        var b = new Unicorn("Different", "99", "LARGE", "COSMIC");
        b.setId(a.getId());

        // if x.equals(y) then y.equals(x)
        assertThat(a.equals(b)).isEqualTo(b.equals(a));
    }

    @Property(tries = 100)
    void transitivity(@ForAll("unicornsWithId") Unicorn a) {
        var b = new Unicorn("B", "2", "MEDIUM", "WATER");
        var c = new Unicorn("C", "3", "SMALL", "FIRE");
        b.setId(a.getId());
        c.setId(a.getId());

        // if x.equals(y) and y.equals(z) then x.equals(z)
        if (a.equals(b) && b.equals(c)) {
            assertThat(a).isEqualTo(c);
        }
    }

    @Property(tries = 100)
    void nullComparison(@ForAll("unicorns") Unicorn unicorn) {
        // x.equals(null) must be false
        assertThat(unicorn.equals(null)).isFalse();
    }

    @Property(tries = 100)
    void hashCodeConsistency(@ForAll("unicorns") Unicorn unicorn) {
        // hashCode must be consistent across multiple calls
        int hash1 = unicorn.hashCode();
        int hash2 = unicorn.hashCode();
        assertThat(hash1).isEqualTo(hash2);
    }

    @Property(tries = 100)
    void equalObjectsHaveSameHashCode(@ForAll("unicornsWithId") Unicorn a) {
        var b = new Unicorn("Different", "99", "LARGE", "COSMIC");
        b.setId(a.getId());

        // if x.equals(y) then x.hashCode() == y.hashCode()
        if (a.equals(b)) {
            assertThat(a.hashCode()).isEqualTo(b.hashCode());
        }
    }

    @Property(tries = 100)
    void differentIdsAreNotEqual(
            @ForAll("unicornsWithId") Unicorn a,
            @ForAll("unicornsWithId") Unicorn b) {

        Assume.that(!a.getId().equals(b.getId()));
        assertThat(a).isNotEqualTo(b);
    }

    @Property(tries = 100)
    void unicornWithNullIdNotEqualToOther(@ForAll("unicorns") Unicorn a) {
        var b = new Unicorn("Other", "5", "MEDIUM", "EARTH");
        b.setId(UUID.randomUUID().toString());

        // Unicorn without ID should not equal unicorn with ID
        assertThat(a).isNotEqualTo(b);
    }

    // --- Providers ---

    @Provide
    Arbitrary<Unicorn> unicorns() {
        return Combinators.combine(
            Arbitraries.strings().alpha().ofMinLength(1).ofMaxLength(20),
            Arbitraries.integers().between(1, 100).map(String::valueOf),
            Arbitraries.of("SMALL", "MEDIUM", "LARGE"),
            Arbitraries.of("EARTH", "WATER", "FIRE", "AIR")
        ).as(Unicorn::new);
    }

    @Provide
    Arbitrary<Unicorn> unicornsWithId() {
        return unicorns().map(u -> {
            u.setId(UUID.randomUUID().toString());
            return u;
        });
    }
}
