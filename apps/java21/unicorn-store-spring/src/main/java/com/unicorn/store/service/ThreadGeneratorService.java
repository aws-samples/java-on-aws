package com.unicorn.store.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

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
            Thread thread = new Thread(new DummyWorkload(running));
            thread.setName("DummyThread-" + i);
            activeThreads.add(thread);
            thread.start();
        }

        logger.info("Started {} threads", threadCount);
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
                thread.join(5000); // Wait up to 5 seconds for each thread
            } catch (InterruptedException e) {
                logger.warn("Interrupted while waiting for thread {} to stop", thread.getName());
            }
        });

        activeThreads.clear();
        logger.info("All threads stopped");
    }

    public int getActiveThreadCount() {
        return activeThreads.size();
    }

    private static class DummyWorkload implements Runnable {
        private final AtomicBoolean running;

        public DummyWorkload(AtomicBoolean running) {
            this.running = running;
        }

        @Override
        public void run() {
            while (running.get()) {
                // Simulate some work
                try {
                    // Calculate some dummy values to keep CPU busy
                    double result = 0;
                    for (int i = 0; i < 1000; i++) {
                        result += Math.sqrt(i) * Math.random();
                    }
                    Thread.sleep(100); // Sleep to prevent excessive CPU usage
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
    }
}
