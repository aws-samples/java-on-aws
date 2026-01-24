package com.example.agent;

import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.web.client.RestClient;

class WeatherTools {

    private static final Logger log = LoggerFactory.getLogger(WeatherTools.class);
    private static final ParameterizedTypeReference<Map<String, Object>> MAP_TYPE =
        new ParameterizedTypeReference<>() {};
    private final RestClient restClient = RestClient.create();

    @Tool(description = """
        Get weather forecast for a city on a specific date.
        Use for answering questions about weather forecasts.
        """)
    public String getWeather(
            @ToolParam(description = "City name, e.g. Paris, London, New York") String city,
            @ToolParam(description = "Date in YYYY-MM-DD format, e.g. 2025-01-27") String date) {
        log.info("getWeather called with city={}, date={}", city, date);
        try {
            var geo = restClient.get()
                .uri("https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1", city)
                .retrieve().body(MAP_TYPE);

            var results = (List<Map<String, Object>>) geo.get("results");
            if (results == null || results.isEmpty()) return "City not found: " + city;

            var loc = results.get(0);
            var weather = restClient.get()
                .uri("https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}" +
                     "&daily=temperature_2m_max,temperature_2m_min&timezone=auto" +
                     "&start_date={startDate}&end_date={endDate}",
                     loc.get("latitude"), loc.get("longitude"), date, date)
                .retrieve().body(MAP_TYPE);

            if (weather.containsKey("error")) {
                var error = "Weather API error: " + weather.get("reason");
                log.warn(error);
                return error;
            }

            var daily = (Map<String, List<Number>>) weather.get("daily");
            var units = (Map<String, String>) weather.get("daily_units");

            var result = "Weather for %s on %s: Min: %.1f%s, Max: %.1f%s".formatted(
                loc.get("name"), date,
                daily.get("temperature_2m_min").get(0).doubleValue(), units.get("temperature_2m_min"),
                daily.get("temperature_2m_max").get(0).doubleValue(), units.get("temperature_2m_max"));
            log.info("getWeather result: {}", result);
            return result;
        } catch (Exception e) {
            log.error("getWeather error", e);
            return "Error fetching weather: " + e.getMessage();
        }
    }
}
