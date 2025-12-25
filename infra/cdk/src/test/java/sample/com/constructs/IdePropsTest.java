package sample.com.constructs;

import net.jqwik.api.*;
import org.junit.jupiter.api.Test;
import sample.com.constructs.Ide.IdeArch;
import sample.com.constructs.Ide.IdeProps;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Property-based tests for Ide construct properties.
 *
 * **Feature: arm64-code-editor-support, Property 1: Architecture determines instance types**
 * **Validates: Requirements 1.2, 1.3, 7.1, 7.2**
 */
public class IdePropsTest {

    /**
     * Property 1: Architecture determines instance types
     * For any architecture value (ARM64 or X86_64), the returned instance type list
     * SHALL contain only instances of the matching architecture family.
     * - ARM64: instance types contain 'g' suffix (m7g, m6g, c7g, t4g)
     * - X86_64: instance types do NOT contain 'g' suffix before size (m7i, m6i, m5, t3)
     */
    @Property(tries = 100)
    void architectureDeterminesInstanceTypes(@ForAll("ideArchProvider") IdeArch arch) {
        // Given
        IdeProps props = IdeProps.builder()
            .ideArch(arch)
            .build();

        // When
        List<String> instanceTypes = props.getInstanceTypes();

        // Then
        assertNotNull(instanceTypes);
        assertFalse(instanceTypes.isEmpty());

        if (arch == IdeArch.ARM64) {
            // ARM64 instances have 'g' suffix (Graviton): m7g, m6g, c7g, t4g
            for (String instanceType : instanceTypes) {
                assertTrue(
                    instanceType.matches(".*[0-9]g\\..*"),
                    "ARM64 instance type should have 'g' suffix (Graviton): " + instanceType
                );
            }
        } else {
            // X86_64 instances do NOT have 'g' suffix before size
            for (String instanceType : instanceTypes) {
                assertFalse(
                    instanceType.matches(".*[0-9]g\\..*"),
                    "X86_64 instance type should NOT have 'g' suffix: " + instanceType
                );
            }
        }
    }

    @Provide
    Arbitrary<IdeArch> ideArchProvider() {
        return Arbitraries.of(IdeArch.ARM64, IdeArch.X86_64);
    }

    /**
     * Unit test: ARM64 returns Graviton instance types
     */
    @Test
    void arm64ReturnsGravitonInstanceTypes() {
        IdeProps props = IdeProps.builder()
            .ideArch(IdeArch.ARM64)
            .build();

        List<String> instanceTypes = props.getInstanceTypes();

        assertEquals(4, instanceTypes.size());
        assertTrue(instanceTypes.contains("m7g.xlarge"));
        assertTrue(instanceTypes.contains("m6g.xlarge"));
        assertTrue(instanceTypes.contains("c7g.xlarge"));
        assertTrue(instanceTypes.contains("t4g.xlarge"));
    }

    /**
     * Unit test: X86_64 returns Intel/AMD instance types
     */
    @Test
    void x86_64ReturnsIntelAmdInstanceTypes() {
        IdeProps props = IdeProps.builder()
            .ideArch(IdeArch.X86_64)
            .build();

        List<String> instanceTypes = props.getInstanceTypes();

        assertEquals(6, instanceTypes.size());
        assertTrue(instanceTypes.contains("m7i-flex.xlarge"));
        assertTrue(instanceTypes.contains("m7a.xlarge"));
        assertTrue(instanceTypes.contains("m6i.xlarge"));
        assertTrue(instanceTypes.contains("m6a.xlarge"));
        assertTrue(instanceTypes.contains("m5.xlarge"));
        assertTrue(instanceTypes.contains("t3.xlarge"));
    }

    /**
     * Unit test: Default architecture is X86_64
     */
    @Test
    void defaultArchitectureIsX86_64() {
        IdeProps props = IdeProps.builder().build();

        assertEquals(IdeArch.X86_64, props.getIdeArch());
        // Should return X86_64 instance types by default
        assertTrue(props.getInstanceTypes().contains("m7i-flex.xlarge"));
    }
}
