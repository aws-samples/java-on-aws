package com.example.perf.collector;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

import java.util.Map;

/**
 * Adds {@code perf.collector.arch} to the Spring environment based on
 * {@code os.arch}. Maps the JVM's reported architecture name to the
 * directory layout bundled under {@code /opt/perf-collector/{amd64,arm64}/}.
 *
 * Registered via {@code META-INF/spring.factories}.
 */
public class ArchPostProcessor implements EnvironmentPostProcessor {

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment env, SpringApplication app) {
        var osArch = System.getProperty("os.arch", "");
        var normalised = switch (osArch) {
            case "amd64", "x86_64" -> "amd64";
            case "aarch64", "arm64" -> "arm64";
            default -> "amd64";  // conservative default
        };
        env.getPropertySources().addFirst(new MapPropertySource(
            "perfCollectorArch",
            Map.of("perf.collector.arch", normalised)));
    }
}
