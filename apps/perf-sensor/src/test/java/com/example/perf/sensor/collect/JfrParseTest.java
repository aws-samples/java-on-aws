package com.example.perf.sensor.collect;

import jdk.jfr.Recording;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Records a real JFR file in the test JVM and asserts the parser reads the JVM's own
 * events (JVMInformation, GC pauses, time span). It also documents a verified limit: a
 * virtual thread blocked in CompletableFuture.get() produces NO jdk.ThreadPark event on
 * JDK 25, which is why request-path blocking is diagnosed from live thread dumps instead.
 */
class JfrParseTest {

    private final JfrCollector collector = new JfrCollector(9100, "com.example.perf.sensor");

    @Test
    void parsesRequestPathParksFromRealRecording() throws Exception {
        Path file = Files.createTempFile("jfr-parse-test", ".jfr");
        try (var rec = new Recording()) {
            rec.enable("jdk.ThreadPark").withThreshold(Duration.ZERO).withStackTrace();
            rec.enable("jdk.JVMInformation");
            rec.enable("jdk.ContainerConfiguration");
            rec.enable("jdk.GCPhasePause").withThreshold(Duration.ZERO);
            rec.start();

            try (var vexec = Executors.newVirtualThreadPerTaskExecutor()) {
                for (int i = 0; i < 3; i++) {
                    vexec.submit(this::blockingPublish).get();
                }
            }
            System.gc();
            rec.stop();
            rec.dump(file);
        }

        var facts = collector.parse(file, "test-pod");
        assertThat(facts.pod()).isEqualTo("test-pod");
        assertThat(facts.recordingStart()).isNotNull();
        assertThat(facts.jvmArgs()).as("jdk.JVMInformation seen (\"\" when the JVM has no -XX args)").isNotNull();

        assertThat(facts.gc()).isNotNull();
        assertThat(facts.pinned()).isNotNull();
        assertThat(facts.compilation()).isNotNull();
        Files.deleteIfExists(file);
    }

    /** A request-path method (this package) that blocks on an async result — the defect shape. */
    private String blockingPublish() {
        var future = CompletableFuture.supplyAsync(() -> {
            try {
                Thread.sleep(40);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            return "ok";
        });
        try {
            return future.get();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
