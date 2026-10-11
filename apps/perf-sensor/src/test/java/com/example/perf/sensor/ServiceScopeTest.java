package com.example.perf.sensor;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Only the configured workloads, and only Kubernetes names, reach a collector or a query. */
class ServiceScopeTest {

    private final ServiceScope scope = ServiceScope.of("shop", "orders");

    @Test
    void configuredWorkloadsPass() {
        assertThatCode(() -> scope.check("shop")).doesNotThrowAnyException();
        assertThatCode(() -> scope.check("orders")).doesNotThrowAnyException();
    }

    @Test
    void anotherWorkloadIsRefused_notMeasuredAsZeroBlocking() {
        assertThatThrownBy(() -> scope.check("billing"))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("not served by this sensor").hasMessageContaining("orders,shop");
    }

    @Test
    void queryTextIsNotAServiceName() {
        assertThatThrownBy(() -> scope.check("x\"}[1m])) or vector(1000) #"))
            .hasMessageContaining("RFC 1123");
        assertThatThrownBy(() -> scope.check("Shop")).hasMessageContaining("RFC 1123");
        assertThatThrownBy(() -> scope.check(null)).hasMessageContaining("RFC 1123");
    }

    @Test
    void anEmptyScopeDoesNotStart() {
        assertThatThrownBy(() -> new ServiceScope(" , ")).isInstanceOf(IllegalStateException.class);
    }
}
