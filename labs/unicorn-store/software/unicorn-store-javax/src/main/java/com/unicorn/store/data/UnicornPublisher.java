package com.unicorn.store.data;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.model.UnicornEventType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.google.gson.Gson;

import javax.enterprise.context.ApplicationScoped;
import javax.inject.Inject;

// import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
// import software.amazon.awssdk.services.eventbridge.EventBridgeAsyncClient;
// import software.amazon.awssdk.services.eventbridge.model.EventBridgeException;
// import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
// import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;

import java.util.concurrent.ExecutionException;

@ApplicationScoped
public class UnicornPublisher {

    private Logger logger = LoggerFactory.getLogger(UnicornPublisher.class.getName());

    // private static final EventBridgeAsyncClient eventBridgeClient = EventBridgeAsyncClient
    //         .builder()
    //         .credentialsProvider(DefaultCredentialsProvider.create())
    //         .build();

    public void publish(Unicorn unicorn, UnicornEventType unicornEventType) {
        try {
            Gson gson = new Gson();
            String unicornJson = gson.toJson(unicorn);
            // var eventsRequest = createEventRequestEntry(unicornEventType, unicornJson);

            // eventBridgeClient.putEvents(eventsRequest).get();
            logger.info("Publishing ... " +  unicornEventType.toString());
            logger.info(unicornJson);
        } catch (Exception e) {
            logger.error("Error Exception ...");
            logger.error(e.getMessage());
        }
    }

    // private PutEventsRequest createEventRequestEntry(UnicornEventType unicornEventType, String unicornJson) {
    //     var entry = PutEventsRequestEntry.builder()
    //             .source("com.unicorn.store")
    //             .eventBusName("unicorns")
    //             .detailType(unicornEventType.name())
    //             .detail(unicornJson)
    //             .build();

    //     return PutEventsRequest.builder()
    //             .entries(entry)
    //             .build();
    // }
}
