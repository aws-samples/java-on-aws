package com.unicorn.store.data;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.services.eventbridge.EventBridgeAsyncClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;
import software.amazon.awssdk.services.eventbridge.model.PutEventsResponse;

import java.util.concurrent.CompletableFuture;

@ApplicationScoped
public class UnicornPublisher {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Logger logger = LoggerFactory.getLogger(getClass());
    private EventBridgeAsyncClient eventBridgeClient;

    @PostConstruct
    public void init() {
        createClient();
    }

    public CompletableFuture<PutEventsResponse> publish(Unicorn unicorn, UnicornEventType unicornEventType) {
        try {
            var unicornJson = objectMapper.writeValueAsString(unicorn);
            logger.debug("Publishing event type: {}", unicornEventType);
            logger.debug("Event payload: {}", unicornJson);

            var eventsRequest = createEventRequestEntry(unicornEventType, unicornJson);
            return eventBridgeClient.putEvents(eventsRequest)
                    .thenApply(response -> {
                        logger.info("Successfully published event type: {} for unicorn ID: {}",
                            unicornEventType, unicorn.getId());
                        return response;
                    })
                    .exceptionally(throwable -> {
                        logger.error("Failed to publish event type: {} for unicorn ID: {}",
                            unicornEventType, unicorn.getId(), throwable);
                        throw new RuntimeException("Failed to publish event", throwable);
                    });
        } catch (JsonProcessingException e) {
            logger.error("Failed to serialize unicorn object", e);
            return CompletableFuture.failedFuture(e);
        }
    }

    private PutEventsRequest createEventRequestEntry(UnicornEventType unicornEventType, String unicornJson) {
        return PutEventsRequest.builder()
                .entries(PutEventsRequestEntry.builder()
                        .source("com.unicorn.store")
                        .eventBusName("unicorns")
                        .detailType(unicornEventType.name())
                        .detail(unicornJson)
                        .build())
                .build();
    }

    private void createClient() {
        logger.info("Creating EventBridgeAsyncClient");

        eventBridgeClient = EventBridgeAsyncClient
                .builder()
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build();
    }

    public void closeClient() {
        logger.info("Closing EventBridgeAsyncClient");
        eventBridgeClient.close();
    }
}
