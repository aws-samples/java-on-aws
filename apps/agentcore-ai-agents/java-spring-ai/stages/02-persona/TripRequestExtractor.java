package com.example.agent;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import org.springframework.ai.chat.client.AdvisorParams;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

/**
 * Extracts a business trip request from an email as structured data.
 * Runs only with the `extract` profile: ./mvnw -q spring-boot:run -Dspring-boot.run.profiles=extract -Dspring-boot.run.arguments=EMAIL_FILE
 */
@Component
@Profile("extract")
class TripRequestExtractor implements ApplicationRunner {

    enum TravelClass { ECONOMY, PREMIUM_ECONOMY, BUSINESS, FIRST }

    // >> The schema: field names, types, and descriptions tell the model what to extract
    record TripRequest(
        @JsonPropertyDescription("Full name of the traveler") String traveler,
        @JsonPropertyDescription("Departure city") String origin,
        @JsonPropertyDescription("Destination city") String destination,
        @JsonPropertyDescription("Outbound travel date") LocalDate departureDate,
        @JsonPropertyDescription("Return travel date") LocalDate returnDate,
        @JsonPropertyDescription("Purpose of the trip, such as the event") String purpose,
        TravelClass travelClass,
        @JsonPropertyDescription("Hotel location or category wishes") String hotelPreference,
        @JsonPropertyDescription("Total trip budget in EUR") Double budgetEur,
        @JsonPropertyDescription("Who approves the trip, such as the manager the email goes to") String approver) {}
    // <<

    private final ChatClient chatClient;

    TripRequestExtractor(ChatClient.Builder chatClientBuilder) {
        this.chatClient = chatClientBuilder.build();
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        String email = Files.readString(Path.of(args.getNonOptionArgs().getFirst()));
        // >> Today's date with the weekday, so the model can turn "the Monday two months from now" into a date
        String today = LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, yyyy-MM-dd", Locale.ENGLISH));
        TripRequest trip = chatClient.prompt()
            .system("Extract the business trip request from the email. Today is " + today + ".")
        // <<
            .user(email)
            // >> Bedrock native structured output; `entity()` returns a validated `TripRequest`
            .advisors(AdvisorParams.ENABLE_NATIVE_STRUCTURED_OUTPUT)
            .call()
            .entity(TripRequest.class);
            // <<
        System.out.println(JsonMapper.builder().findAndAddModules().build()
            .writerWithDefaultPrettyPrinter().writeValueAsString(trip));
    }
}
