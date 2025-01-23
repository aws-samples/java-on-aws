package com.unicorn.store.data;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;

import jakarta.annotation.PostConstruct;
import org.crac.Context;
import org.crac.Resource;
import org.crac.Core;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.services.eventbridge.EventBridgeAsyncClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;
import software.amazon.awssdk.services.eventbridge.model.PutEventsResponse;

import java.util.concurrent.CompletableFuture;

@Service
public final class UnicornPublisher implements Resource {

    private final ObjectMapper objectMapper;

    private final Logger logger = LoggerFactory.getLogger(UnicornPublisher.class);

    private EventBridgeAsyncClient eventBridgeClient;

    public UnicornPublisher(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @PostConstruct
    public void init() {
        createClient();
        Core.getGlobalContext().register(this);
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

    @Override
    public void beforeCheckpoint(Context<? extends Resource> context) throws Exception {
        logger.info("Executing beforeCheckpoint...");
        closeClient();
    }

    @Override
    public void afterRestore(Context<? extends Resource> context) throws Exception {
        logger.info("Executing afterRestore ...");
        createClient();
    }
}
