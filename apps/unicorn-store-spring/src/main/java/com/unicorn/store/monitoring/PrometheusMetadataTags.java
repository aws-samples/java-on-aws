package com.unicorn.store.monitoring;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

@Component
public class PrometheusMetadataTags {

    private final MeterRegistry meterRegistry;
    private final ObjectMapper objectMapper = new ObjectMapper();

    private final Logger logger = LoggerFactory.getLogger(PrometheusMetadataTags.class);

    public PrometheusMetadataTags(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void configureCommonTagsFromEcsMetadata() {
        try {
            String metadataUri = System.getenv("ECS_CONTAINER_METADATA_URI_V4");
            if (metadataUri == null || metadataUri.isEmpty()) {
                logger.error("ECS_CONTAINER_METADATA_URI_V4 is not set.");
                return;
            }

            String taskMetadataUrl = metadataUri + "/task";

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(taskMetadataUrl))
                    .GET()
                    .build();

            HttpClient client = HttpClient.newHttpClient();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 200) {
                logger.error("Failed to fetch ECS metadata. Status: " + response.statusCode());
                return;
            }

            JsonNode root = objectMapper.readTree(response.body());

            String taskArn = root.path("TaskARN").asText();
            String taskId = taskArn.substring(taskArn.lastIndexOf('/') + 1);

            String containerName = root.path("Containers").get(0).path("Name").asText();

            String clusterArn = root.path("Cluster").asText();
            String clusterName = clusterArn.substring(clusterArn.lastIndexOf('/') + 1);

            meterRegistry.config().commonTags(
                    "ecs_task_id", taskId,
                    "ecs_container_name", containerName,
                    "ecs_cluster", clusterName
            );

            logger.info("Micrometer common tags set from ECS metadata.");

        } catch (Exception e) {
            logger.error("Failed to set ECS metadata tags: " + e.getMessage());
        }
    }
}
