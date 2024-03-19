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
import software.amazon.awssdk.services.eventbridge.model.EventBridgeException;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;


@Service
public class UnicornPublisher implements Resource {

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

    public void publish(Unicorn unicorn, UnicornEventType unicornEventType) {
        try {
            var unicornJson = objectMapper.writeValueAsString(unicorn);
            logger.info("Publishing ... " + unicornEventType.toString());
            logger.info(unicornJson);

            var eventsRequest = createEventRequestEntry(unicornEventType, unicornJson);
            // eventBridgeClient.putEvents(eventsRequest).get();
        } catch (JsonProcessingException e) {
            logger.error("Error JsonProcessingException ...");
            logger.error(e.getMessage());
        } catch (EventBridgeException e) {
            logger.error("Error EventBridgeException | ExecutionException ...");
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
