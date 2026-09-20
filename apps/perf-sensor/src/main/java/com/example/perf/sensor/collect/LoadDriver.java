package com.example.perf.sensor.collect;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Drives a bounded, rate-based write load directly at a pod (open model, like Artillery
 * {@code arrivalRate}) so a blocking call on the request path actually manifests while the
 * sensor samples a thread dump. Rate-based (not closed-loop concurrency) with an in-flight cap
 * so it never saturates a small, right-sized pod: ~{@code ratePerSec} requests per second, each
 * fired on a virtual thread and NOT awaited (a slow request does not throttle arrivals).
 *
 * <p>Writes have side effects (creates/updates resources); intended for a pre-prod workshop env.
 * The write path and JSON payload are configurable; defaults match the unicorn-store benchmark.
 */
@Component
public class LoadDriver {

    private static final Logger logger = LoggerFactory.getLogger(LoadDriver.class);

    private final int port;
    private final String path;
    private final String payload;
    private final int inFlightCap;
    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(2)).build();

    public LoadDriver(
        @Value("${LOAD_PORT:8080}") int port,
        @Value("${LOAD_PATH:/unicorns}") String path,
        @Value("${LOAD_PAYLOAD:{\"name\":\"Big Unicorn\",\"age\":\"Quite old\",\"type\":\"Beautiful\",\"size\":\"Very big\"}}") String payload,
        @Value("${LOAD_INFLIGHT_CAP:200}") int inFlightCap) {
        this.port = port;
        this.path = path;
        this.payload = payload;
        this.inFlightCap = inFlightCap;
    }

    /** Handle to a running load; {@link #close()} stops arrivals and reports how many were sent. */
    public final class Handle implements AutoCloseable {
        private final ScheduledExecutorService scheduler;
        private final java.util.concurrent.ExecutorService workers;
        final AtomicInteger sent = new AtomicInteger();
        final AtomicInteger ok = new AtomicInteger();
        final AtomicInteger failed = new AtomicInteger();

        Handle(ScheduledExecutorService scheduler, java.util.concurrent.ExecutorService workers) {
            this.scheduler = scheduler;
            this.workers = workers;
        }

        public int sent() {
            return sent.get();
        }

        public int ok() {
            return ok.get();
        }

        public int failed() {
            return failed.get();
        }

        @Override
        public void close() {
            scheduler.shutdownNow();
            workers.shutdown();
            try {
                workers.awaitTermination(3, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            logger.info("LoadDriver stopped: sent={} ok={} failed={}", sent.get(), ok.get(), failed.get());
        }
    }

    /**
     * Start firing ~{@code ratePerSec} POSTs/sec at {@code http://podIp:port/path}. Returns a
     * {@link Handle} — close it to stop. Rate is clamped to [1, 100]/sec to protect small pods.
     */
    public Handle start(String podIp, int ratePerSec) {
        int rate = Math.max(1, Math.min(ratePerSec <= 0 ? 25 : ratePerSec, 100));
        long periodMicros = 1_000_000L / rate;
        URI uri = URI.create("http://" + podIp + ":" + port + path);
        var workers = Executors.newVirtualThreadPerTaskExecutor();
        var inFlight = new Semaphore(inFlightCap);
        var scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            var t = new Thread(r, "load-driver");
            t.setDaemon(true);
            return t;
        });
        var handle = new Handle(scheduler, workers);
        scheduler.scheduleAtFixedRate(() -> {
            if (!inFlight.tryAcquire()) {
                return;   // app is stalling; don't pile on (protects a saturating pod)
            }
            handle.sent.incrementAndGet();
            workers.submit(() -> {
                try {
                    var req = HttpRequest.newBuilder(uri)
                        .timeout(Duration.ofSeconds(29))
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(payload))
                        .build();
                    var resp = http.send(req, HttpResponse.BodyHandlers.discarding());
                    if (resp.statusCode() < 400) {
                        handle.ok.incrementAndGet();
                    } else {
                        handle.failed.incrementAndGet();
                    }
                } catch (Exception e) {
                    handle.failed.incrementAndGet();
                } finally {
                    inFlight.release();
                }
            });
        }, 0, periodMicros, TimeUnit.MICROSECONDS);
        logger.info("LoadDriver started: {} at {}/sec", uri, rate);
        return handle;
    }
}
