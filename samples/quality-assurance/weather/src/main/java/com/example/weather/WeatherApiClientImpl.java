package com.example.weather;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.server.ResponseStatusException;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;

/**
 * Implementation of WeatherApiClient that makes actual HTTP calls to external weather APIs.
 */
@Component
public class WeatherApiClientImpl implements WeatherApiClient {
    private static final Logger logger = LoggerFactory.getLogger(WeatherApiClientImpl.class);
    private final WebClient webClient;

    public WeatherApiClientImpl(WebClient.Builder webClientBuilder) {
        this.webClient = webClientBuilder.build();
    }

    @Override
    public Map<?, ?> getGeocodingData(String city) {
        String encodedCity = URLEncoder.encode(city, StandardCharsets.UTF_8);
        String url = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodedCity + "&count=1";

        logger.debug("Calling geocoding API: {}", url);

        try {
            return webClient.get()
                .uri(url)
                .retrieve()
                .bodyToMono(Map.class)
                .timeout(Duration.ofSeconds(15))
                .block();
        } catch (Exception e) {
            logger.warn("Error calling geocoding service: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Error connecting to geocoding service: " + e.getMessage());
        }
    }

    @Override
    public Map<?, ?> getWeatherData(double latitude, double longitude, String date) {
        String url = String.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date=%s&end_date=%s",
            latitude, longitude, date, date
        );

        logger.debug("Calling weather API: {}", url);

        try {
            return webClient.get()
                .uri(url)
                .retrieve()
                .bodyToMono(Map.class)
                .timeout(Duration.ofSeconds(15))
                .block();
        } catch (Exception e) {
            logger.warn("Error calling weather service: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Error connecting to weather service: " + e.getMessage());
        }
    }
}