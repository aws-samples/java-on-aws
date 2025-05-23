package com.unicorn.store.config;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.config.MeterFilter;
import org.springframework.boot.actuate.autoconfigure.metrics.MeterRegistryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.util.Optional;

@Configuration
public class MonitoringConfig {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final File NAMESPACE_FILE = new File("/var/run/secrets/kubernetes.io/serviceaccount/namespace");

    @Bean
    public MeterRegistryCustomizer<MeterRegistry> meterRegistryCustomizer() {
        return registry -> {
            String cluster = Optional.ofNullable(System.getenv("CLUSTER")).orElse("unknown");
            String containerName = "unicorn-store-spring";
            String taskOrPodId = extractTaskOrPodId().orElse("unknown");
            String clusterType = System.getenv("ECS_CONTAINER_METADATA_URI_V4") != null ? "ecs" : "eks";
            String namespace = clusterType.equals("eks") ? readNamespaceFile().orElse("default") : "";

            registry.config().commonTags(
                    "cluster", cluster,
                    "cluster_type", clusterType,
                    "container_name", containerName,
                    "task_pod_id", taskOrPodId
            );

            if (!namespace.isEmpty()) {
                registry.config().commonTags("namespace", namespace);
            } else {
                registry.config().commonTags("namespace", "<no namespace>");
            }

            registry.config().meterFilter(
                    MeterFilter.deny(id ->
                            id.getName().equals("jvm.gc.pause") &&
                                    !id.getTags().stream().allMatch(tag ->
                                            tag.getKey().equals("action") ||
                                                    tag.getKey().equals("cause") ||
                                                    tag.getKey().equals("gc")
                                    )
                    )
            );
        };
    }

    private Optional<String> extractTaskOrPodId() {
        String metadataUri = System.getenv("ECS_CONTAINER_METADATA_URI_V4");
        if (metadataUri != null) {
            try {
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(metadataUri + "/task"))
                        .build();

                HttpResponse<String> response = HttpClient.newHttpClient()
                        .send(request, HttpResponse.BodyHandlers.ofString());

                JsonNode root = OBJECT_MAPPER.readTree(response.body());
                String taskArn = root.path("TaskARN").asText();
                String[] parts = taskArn.split("/");
                return parts.length > 1 ? Optional.of(parts[parts.length - 1]) : Optional.empty();

            } catch (IOException | InterruptedException e) {
                return Optional.empty();
            }
        }

        // EKS fallback: read pod name from Downward API
        return readFile("/etc/podinfo/name");
    }

    private Optional<String> readNamespaceFile() {
        return readFile(NAMESPACE_FILE.getAbsolutePath());
    }

    private Optional<String> readFile(String path) {
        try {
            return Optional.of(Files.readString(new File(path).toPath()).trim());
        } catch (IOException e) {
            return Optional.empty();
        }
    }
}