package com.example.weather;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.Collections;
import java.util.List;
import java.util.Map;

@Service
public class WeatherService {
    private static final Logger logger = LoggerFactory.getLogger(WeatherService.class);
    private final WeatherApiClient apiClient;

    public WeatherService(WeatherApiClient apiClient) {
        this.apiClient = apiClient;
    }

    /**
     * Get weather forecast for a city on a specific date
     *
     * @param city The city name
     * @param date The date in YYYY-MM-DD format
     * @return Weather forecast with min/max temperatures
     */
    public String getWeather(String city, String date) {
        if (city == null || city.trim().isEmpty()) {
            logger.warn("Weather request failed: city parameter is missing");
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "City parameter is required");
        }

        try {
            LocalDate.parse(date);
        } catch (Exception e) {
            logger.warn("Weather request failed: invalid date format: {}", date);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid date format. Use YYYY-MM-DD");
        }

        String cleanCity = city.trim();
        logger.debug("Fetching geocoding data for city: {}", cleanCity);

        // Get city coordinates using the API client
        Map<?, ?> geocodingResponse = apiClient.getGeocodingData(cleanCity);

        // Extract city data
        List<?> results = Collections.emptyList();
        if (geocodingResponse != null && geocodingResponse.containsKey("results")) {
            Object resultsObj = geocodingResponse.get("results");
            if (resultsObj instanceof List) {
                results = (List<?>) resultsObj;
            }
        }

        if (results.isEmpty()) {
            logger.warn("Weather request failed: city not found: {}", cleanCity);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "City not found: " + cleanCity);
        }

        var location = (Map<?, ?>) results.get(0);
        var latitude = ((Number) location.get("latitude")).doubleValue();
        var longitude = ((Number) location.get("longitude")).doubleValue();
        var cityName = (String) location.get("name");
        var country = location.get("country") != null ? (String) location.get("country") : "";

        logger.debug("Found location: {}, {}, coordinates: {}, {}",
            cityName, country, latitude, longitude);

        // Get weather data using the API client
        Map<?, ?> weatherResponse = apiClient.getWeatherData(latitude, longitude, date);

        if (weatherResponse == null) {
            logger.warn("Weather request failed: no response from weather service");
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "No response from weather service");
        }

        // Extract weather data
        var dailyData = (Map<?, ?>) weatherResponse.get("daily");
        var dailyUnits = (Map<?, ?>) weatherResponse.get("daily_units");

        if (dailyData == null || dailyUnits == null) {
            logger.warn("Weather request failed: invalid weather data format");
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Invalid weather data format");
        }

        var maxTempList = (List<?>) dailyData.get("temperature_2m_max");
        var minTempList = (List<?>) dailyData.get("temperature_2m_min");

        if (maxTempList == null || minTempList == null || maxTempList.isEmpty() || minTempList.isEmpty()) {
            logger.warn("Weather request failed: no temperature data for date: {}", date);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No temperature data for this date");
        }

        var maxTemp = ((Number) maxTempList.get(0)).doubleValue();
        var minTemp = ((Number) minTempList.get(0)).doubleValue();
        var unit = (String) dailyUnits.get("temperature_2m_max");

        String locationDisplay = cityName + (country.isEmpty() ? "" : ", " + country);
        String formattedUnit = unit.replace("°", " deg ");

        logger.info("Retrieved weather for {}, {}: date: {}, min: {}{}, max: {}{}",
            cityName, country, date, minTemp, formattedUnit, maxTemp, formattedUnit);

        return String.format(
            "Weather for %s on %s:\nMin: %.1f%s, Max: %.1f%s",
            locationDisplay, date, minTemp, formattedUnit, maxTemp, formattedUnit
        );
    }
}