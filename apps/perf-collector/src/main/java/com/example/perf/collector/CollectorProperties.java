package com.example.perf.collector;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Bound from perf.collector.* in application.yaml.
 *
 * Domain types the rest of the package uses (Platform, DumpKind, TargetJvm)
 * are defined as inner types here so the package is flat — no domain/ folder.
 */
@ConfigurationProperties(prefix = "perf.collector")
public record CollectorProperties(
    String pyroscopeUrl,
    String s3Bucket,
    int discoveryIntervalSeconds,
    String nodeName,
    Platform platform,
    String asyncProfilerLib,
    String jattachBinary,
    String asprofBinary,
    String jfrconvBinary,
    String hostLibPath
) {

    public enum Platform { EKS, ECS }

    public enum DumpKind {
        JFR("jfr"),
        THREAD_DUMP("threaddump");

        private final String wire;
        DumpKind(String wire) { this.wire = wire; }
        @JsonValue public String wireValue() { return wire; }

        @JsonCreator
        public static DumpKind fromWire(String v) {
            for (var k : values()) if (k.wire.equalsIgnoreCase(v)) return k;
            throw new IllegalArgumentException("Unknown DumpKind: " + v);
        }
    }

    /** A discovered JVM we own (opted in via perf-profile/service label or tag). */
    public record TargetJvm(
        long pid,
        String serviceName,
        String version,
        String idLabel,   // pod name (EKS) or task id (ECS)
        Platform platform
    ) {}
}
