package com.example.perf.sensor.collect;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** The Spring Boot startup line regex, including the CRaC restore forms and the no-line case. */
class LogParseTest {

    @Test
    void noLine_isNull() {
        assertThat(LogCollector.parse(null)).isNull();
        assertThat(LogCollector.parse("")).isNull();
        assertThat(LogCollector.parse("INFO  Tomcat started on port 8080")).isNull();
    }

    @Test
    void started_line() {
        var l = LogCollector.parse("x\n2026-09-22T05:50:41.445Z  INFO 7 --- [main] c.u.s.StoreApplication : Started StoreApplication in 6.921 seconds (process running for 7.562)\n");
        assertThat(l.kind()).isEqualTo("Started");
        assertThat(l.seconds()).isEqualTo(6.921);
    }

    @Test
    void restored_onRefresh_line() {
        var l = LogCollector.parse("Restored StoreApplication in 0.142 seconds (process running for 0.143)");
        assertThat(l.kind()).isEqualTo("Restored");
        assertThat(l.seconds()).isEqualTo(0.142);
    }

    @Test
    void restored_jcmdCheckpoint_line_winsOverBuildTimeStarted() {
        // A checkpoint taken after startup replays the build-time "Started" line first; the
        // lifecycle-restart line is what the restore actually took.
        var l = LogCollector.parse("""
            Started StoreApplication in 6.548 seconds (process running for 7.183)
            14572.734781: warp: Restore successful!
            2026-09-22T09:06:03.951Z  INFO 7 --- [Attach Listener] o.s.c.support.DefaultLifecycleProcessor  : Spring-managed lifecycle restart completed (restored JVM running for 61 ms)
            """);
        assertThat(l.kind()).isEqualTo("Restored");
        assertThat(l.seconds()).isEqualTo(0.061);
        assertThat(l.line()).contains("restored JVM running for 61 ms");
    }
}
