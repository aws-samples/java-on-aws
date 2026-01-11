package com.unicorn.store.property;

import com.unicorn.store.context.RequestContext;
import net.jqwik.api.*;
import net.jqwik.api.constraints.IntRange;

import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.assertThat;

// Property tests for Scoped Values (JEP 506) - validates thread isolation
class RequestContextPropertyTest {

    @Property(tries = 100)
    @Label("Concurrent requests receive unique request IDs")
    void concurrentRequestsReceiveUniqueIds(@ForAll @IntRange(min = 2, max = 50) int numRequests)
            throws InterruptedException {
        Set<String> capturedIds = ConcurrentHashMap.newKeySet();
        CountDownLatch startLatch = new CountDownLatch(1);
        CountDownLatch doneLatch = new CountDownLatch(numRequests);

        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < numRequests; i++) {
                executor.submit(() -> {
                    try {
                        startLatch.await();
                        String requestId = UUID.randomUUID().toString();

                        ScopedValue.where(RequestContext.REQUEST_ID, requestId).run(() -> {
                            String capturedId = RequestContext.REQUEST_ID.orElse("missing");
                            capturedIds.add(capturedId);
                        });
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    } finally {
                        doneLatch.countDown();
                    }
                });
            }

            startLatch.countDown();
            doneLatch.await();
        }

        assertThat(capturedIds)
            .as("All %d concurrent requests should have unique IDs", numRequests)
            .hasSize(numRequests);
    }

    @Property(tries = 100)
    @Label("Scoped Value returns bound value within scope")
    void scopedValueReturnsCorrectValue(@ForAll("uuids") String expectedId) {
        ScopedValue.where(RequestContext.REQUEST_ID, expectedId).run(() -> {
            String actualId = RequestContext.REQUEST_ID.orElse("missing");
            assertThat(actualId).isEqualTo(expectedId);
        });
    }

    @Property(tries = 100)
    @Label("Scoped Value returns default outside scope")
    void scopedValueReturnsDefaultOutsideScope(@ForAll("defaults") String defaultValue) {
        String actualId = RequestContext.REQUEST_ID.orElse(defaultValue);
        assertThat(actualId).isEqualTo(defaultValue);
    }

    @Provide
    Arbitrary<String> uuids() {
        return Arbitraries.create(() -> UUID.randomUUID().toString());
    }

    @Provide
    Arbitrary<String> defaults() {
        return Arbitraries.of("no-request-id", "unknown", "default", "N/A");
    }
}
