package com.example.ai.agent.tool;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.util.Collections;
import java.util.List;
import java.util.Map;

@Service
public class WeatherService {
    private static final Logger logger = LoggerFactory.getLogger(WeatherService.class);
    private final WebClient webClient;

    public WeatherService(WebClient.Builder webClientBuilder) {
        this.webClient = webClientBuilder.build();
    }

    @Tool(description = """
        Get weather forecast for a city on a specific date.
        Requires:
        - city: City name (e.g., 'London', 'Paris', 'New York')
        - date: Date in YYYY-MM-DD format
        Returns: Weather forecast with minimum and maximum temperatures.

        Examples:
        - getWeather("London", "2025-11-10")
        - getWeather("Paris", "2025-11-15")

        Use this tool when users ask about weather conditions for travel planning.
        """)
    public String getWeather(String city, String date) {
        if (city == null || city.trim().isEmpty()) {
            return "Error: City parameter is required";
        }

        try {
            LocalDate.parse(date);
        } catch (Exception e) {
            return "Error: Invalid date format. Use YYYY-MM-DD";
        }

        logger.info("Fetching weather for city: {}, date: {}", city, date);

        try {
            // Get city coordinates
            String encodedCity = URLEncoder.encode(city.trim(), StandardCharsets.UTF_8);
            String geocodingUrl = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodedCity + "&count=1";

            Map<?, ?> geocodingResponse = webClient.get()
                    .uri(geocodingUrl)
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofSeconds(15))
                    .block();

            List<?> results = Collections.emptyList();
            if (geocodingResponse != null && geocodingResponse.containsKey("results")) {
                Object resultsObj = geocodingResponse.get("results");
                if (resultsObj instanceof List) {
                    results = (List<?>) resultsObj;
                }
            }

            if (results.isEmpty()) {
                return "Error: City not found: " + city;
            }

            var location = (Map<?, ?>) results.get(0);
            var latitude = ((Number) location.get("latitude")).doubleValue();
            var longitude = ((Number) location.get("longitude")).doubleValue();
            var cityName = (String) location.get("name");
            var country = location.get("country") != null ? (String) location.get("country") : "";

            // Get weather data
            String weatherUrl = String.format(
                    "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date=%s&end_date=%s",
                    latitude, longitude, date, date
            );

            Map<?, ?> weatherResponse = webClient.get()
                    .uri(weatherUrl)
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofSeconds(15))
                    .block();

            if (weatherResponse == null) {
                return "Error: No response from weather service";
            }

            var dailyData = (Map<?, ?>) weatherResponse.get("daily");
            var dailyUnits = (Map<?, ?>) weatherResponse.get("daily_units");

            if (dailyData == null || dailyUnits == null) {
                return "Error: Invalid weather data format";
            }

            var maxTempList = (List<?>) dailyData.get("temperature_2m_max");
            var minTempList = (List<?>) dailyData.get("temperature_2m_min");

            if (maxTempList == null || minTempList == null || maxTempList.isEmpty() || minTempList.isEmpty()) {
                return "Error: No temperature data for date: " + date;
            }

            var maxTemp = ((Number) maxTempList.get(0)).doubleValue();
            var minTemp = ((Number) minTempList.get(0)).doubleValue();
            var unit = (String) dailyUnits.get("temperature_2m_max");

            String locationDisplay = cityName + (country.isEmpty() ? "" : ", " + country);
            String formattedUnit = unit.replace("°", " deg ");

            logger.info("Retrieved weather for {}: min: {}{}, max: {}{}",
                    locationDisplay, minTemp, formattedUnit, maxTemp, formattedUnit);

            return String.format(
                    "Weather for %s on %s:\nMin: %.1f%s, Max: %.1f%s",
                    locationDisplay, date, minTemp, formattedUnit, maxTemp, formattedUnit
            );

        } catch (Exception e) {
            logger.error("Error fetching weather for city: {}, date: {}", city, date, e);
            return "Error: Unable to fetch weather data - " + e.getMessage();
        }
    }
}
