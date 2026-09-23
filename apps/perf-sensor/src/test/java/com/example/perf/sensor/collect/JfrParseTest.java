package com.example.perf.sensor.collect;

import jdk.jfr.Recording;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Records a real JFR file in the test JVM and asserts the parser reads the JVM's own events
 * (JVMInformation, GC pauses, time span) and masks credential-looking system properties in
 * {@code jvmArgs}. Request-path blocking is NOT read from JFR on purpose: JDK 25 emits
 * {@code jdk.ThreadPark} for platform threads only, so a parked virtual thread leaves nothing
 * in the ring; that diagnosis lives in {@code diagnoseBlocking} (live JSON thread dumps).
 */
class JfrParseTest {

    private final JfrCollector collector = new JfrCollector(9100, "com.example.perf.sensor");

    @Test
    void parsesJvmEventsFromARealRecording() throws Exception {
        Path file = Files.createTempFile("jfr-parse-test", ".jfr");
        try (var rec = new Recording()) {
            rec.enable("jdk.JVMInformation");
            rec.enable("jdk.ContainerConfiguration");
            rec.enable("jdk.GCPhasePause").withThreshold(Duration.ZERO);
            rec.start();
            System.gc();
            rec.stop();
            rec.dump(file);
        }
        try {
            var facts = collector.parse(file, "test-pod");
            assertThat(facts.pod()).isEqualTo("test-pod");
            assertThat(facts.recordingStart()).isNotNull();
            assertThat(facts.jvmArgs()).as("jdk.JVMInformation seen (\"\" when the JVM has no -XX args)").isNotNull();
            assertThat(facts.gc()).isNotNull();
            assertThat(facts.pinned()).isNotNull();
            assertThat(facts.compilation()).isNotNull();
        } finally {
            Files.deleteIfExists(file);
        }
    }

    @Test
    void jvmArgs_credentialValuesAreMasked_flagNamesStay() {
        String args = "-Xmx512m -Dspring.datasource.password=s3cr3t -Dapi.token=abc.def -Dserver.port=8080 -DAPI_KEY=xyz";
        assertThat(JfrCollector.redact(args))
            .isEqualTo("-Xmx512m -Dspring.datasource.password=*** -Dapi.token=*** -Dserver.port=8080 -DAPI_KEY=***");
    }

    @Test
    void requestPackageIsRequired() {
        assertThatThrownBy(() -> new JfrCollector(9100, " "))
            .isInstanceOf(IllegalStateException.class);
    }
}
