package com.unicorn.store.config;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.config.MeterFilter;
import org.springframework.boot.actuate.autoconfigure.metrics.MeterRegistryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Optional;

@Configuration
public class MonitoringConfig {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Bean
    public MeterRegistryCustomizer<MeterRegistry> meterRegistryCustomizer() {
        return registry -> {
            String cluster = System.getenv("ECS_CLUSTER");
            String containerName = "unicorn-store-spring";
            String taskId = extractTaskIdFromMetadata().orElse("unknown");

            registry.config().commonTags(
                    "ecs_cluster", cluster,
                    "ecs_container_name", containerName,
                    "ecs_task_id", taskId
            );

            // Avoid duplicate meters
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

    private Optional<String> extractTaskIdFromMetadata() {
        String metadataUri = System.getenv("ECS_CONTAINER_METADATA_URI_V4");
        if (metadataUri == null) {
            return Optional.empty();
        }

        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(metadataUri + "/task"))
                    .build();

            HttpResponse<String> response = HttpClient.newHttpClient()
                    .send(request, HttpResponse.BodyHandlers.ofString());

            JsonNode root = OBJECT_MAPPER.readTree(response.body());
            String taskArn = root.path("TaskARN").asText();

            // Extract task ID from ARN: arn:aws:ecs:region:account:task/task-id
            String[] parts = taskArn.split("/");
            return parts.length > 1 ? Optional.of(parts[parts.length - 1]) : Optional.empty();

        } catch (IOException | InterruptedException e) {
            return Optional.empty();
        }
    }
}
