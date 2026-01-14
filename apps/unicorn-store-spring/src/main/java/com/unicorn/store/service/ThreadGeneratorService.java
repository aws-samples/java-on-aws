package com.unicorn.store.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

// Virtual thread generator for profiling - uses Thread.ofVirtual() (Java 21+)
@Service
public class ThreadGeneratorService {
    private static final Logger logger = LoggerFactory.getLogger(ThreadGeneratorService.class);
    private final List<Thread> activeThreads = new ArrayList<>();
    private final AtomicBoolean running = new AtomicBoolean(false);

    public synchronized void startThreads(int threadCount) {
        if (running.get()) {
            throw new IllegalStateException("Threads are already running");
        }

        running.set(true);
        logger.info("Starting {} threads", threadCount);

        for (int i = 0; i < threadCount; i++) {
            var thread = Thread.ofPlatform()
                    .name("DummyThread-" + i)
                    .start(new DummyWorkload(running));
            activeThreads.add(thread);
        }

        logger.info("Started {} platform threads", threadCount);
    }

    public synchronized void stopThreads() {
        if (!running.get()) {
            throw new IllegalStateException("No threads are running");
        }

        logger.info("Stopping {} threads", activeThreads.size());
        running.set(false);

        // Wait for all threads to complete
        activeThreads.forEach(thread -> {
            try {
                thread.join(java.time.Duration.ofSeconds(5));
            } catch (InterruptedException ignored) {
                logger.warn("Interrupted while waiting for thread {} to stop", thread.getName());
                Thread.currentThread().interrupt();
            }
        });

        activeThreads.clear();
        logger.info("All threads stopped");
    }

    public int getActiveThreadCount() {
        return activeThreads.size();
    }

    // Dummy workload for profiling - volatile blackhole prevents JIT elimination
    private static class DummyWorkload implements Runnable {
        private final AtomicBoolean running;
        @SuppressWarnings("unused")
        private static volatile double blackhole;

        DummyWorkload(AtomicBoolean running) {
            this.running = running;
        }

        @Override
        public void run() {
            while (running.get()) {
                try {
                    var result = 0.0;
                    for (int i = 0; i < 1000; i++) {
                        result += Math.sqrt(i) * Math.random();
                    }
                    blackhole = result;
                    Thread.sleep(java.time.Duration.ofMillis(100));
                } catch (InterruptedException ignored) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
    }
}