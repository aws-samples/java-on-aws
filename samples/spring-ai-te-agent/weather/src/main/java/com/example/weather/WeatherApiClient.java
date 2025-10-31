package com.example.weather;

import java.util.Map;

/**
 * Interface for weather API client to abstract external API calls
 * for better testability and decoupling.
 */
public interface WeatherApiClient {

    /**
     * Get geocoding data for a city
     *
     * @param city The city name to get coordinates for
     * @return Map containing geocoding response data
     */
    Map<?, ?> getGeocodingData(String city);

    /**
     * Get weather data for specific coordinates and date
     *
     * @param latitude The latitude coordinate
     * @param longitude The longitude coordinate
     * @param date The date in YYYY-MM-DD format
     * @return Map containing weather response data
     */
    Map<?, ?> getWeatherData(double latitude, double longitude, String date);
}