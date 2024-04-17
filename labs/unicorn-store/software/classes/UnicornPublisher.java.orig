package com.unicorn.store.data;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;

import jakarta.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.services.eventbridge.EventBridgeAsyncClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;


@Service
public class UnicornPublisher {

    private final ObjectMapper objectMapper;

    private final Logger logger = LoggerFactory.getLogger(UnicornPublisher.class);

    private EventBridgeAsyncClient eventBridgeClient;

    public UnicornPublisher(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @PostConstruct
    public void init() {
        createClient();
    }

    public void publish(Unicorn unicorn, UnicornEventType unicornEventType) {
        try {
            var unicornJson = objectMapper.writeValueAsString(unicorn);
            logger.info("Publishing ... " + unicornEventType.toString());
            logger.info(unicornJson);

            var eventsRequest = createEventRequestEntry(unicornEventType, unicornJson);
            eventBridgeClient.putEvents(eventsRequest).get();
        } catch (Exception e) {
            logger.error("Error ...");
            logger.error(e.getMessage());
        }
    }

    private PutEventsRequest createEventRequestEntry(UnicornEventType unicornEventType, String unicornJson) {
        var entry = PutEventsRequestEntry.builder()
                .source("com.unicorn.store")
                .eventBusName("unicorns")
                .detailType(unicornEventType.name())
                .detail(unicornJson)
                .build();

        return PutEventsRequest.builder()
                .entries(entry)
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
