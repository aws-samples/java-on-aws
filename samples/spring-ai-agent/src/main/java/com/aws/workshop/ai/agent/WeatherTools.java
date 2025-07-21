package com.aws.workshop.ai.agent;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

import org.json.JSONObject;
import org.springframework.ai.tool.annotation.Tool;

public class WeatherTools {

    private final HttpClient httpClient = HttpClient.newHttpClient();

    @Tool(description = "Get weather forecast for a city on a specific date (format: YYYY-MM-DD)")
    String getWeather(String city, String date) {
        try {
            // Convert city to coordinates using Geocoding API
            String encodedCity = java.net.URLEncoder.encode(city, java.nio.charset.StandardCharsets.UTF_8);
            String geocodingUrl = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodedCity + "&count=1";
            HttpRequest geocodingRequest = HttpRequest.newBuilder()
                    .uri(URI.create(geocodingUrl))
                    .GET()
                    .build();

            HttpResponse<String> geocodingResponse = httpClient.send(geocodingRequest, HttpResponse.BodyHandlers.ofString());
            JSONObject geocodingJson = new JSONObject(geocodingResponse.body());

            if (geocodingJson.getJSONArray("results").isEmpty()) {
                return "City not found";
            }

            JSONObject location = geocodingJson.getJSONArray("results").getJSONObject(0);
            double latitude = location.getDouble("latitude");
            double longitude = location.getDouble("longitude");

            // Parse and validate date
            LocalDate forecastDate;
            try {
                forecastDate = LocalDate.parse(date, DateTimeFormatter.ISO_LOCAL_DATE);
            } catch (Exception e) {
                return "Invalid date format. Please use YYYY-MM-DD format.";
            }

            // Get weather data from Open-Meteo API
            String weatherUrl = "https://api.open-meteo.com/v1/forecast" +
                    "?latitude=" + latitude +
                    "&longitude=" + longitude +
                    "&daily=temperature_2m_max,temperature_2m_min" +
                    "&timezone=auto" +
                    "&start_date=" + date +
                    "&end_date=" + date;

            HttpRequest weatherRequest = HttpRequest.newBuilder()
                    .uri(URI.create(weatherUrl))
                    .GET()
                    .build();

            HttpResponse<String> weatherResponse = httpClient.send(weatherRequest, HttpResponse.BodyHandlers.ofString());
            JSONObject weatherJson = new JSONObject(weatherResponse.body());

            double maxTemp = weatherJson.getJSONObject("daily").getJSONArray("temperature_2m_max").getDouble(0);
            double minTemp = weatherJson.getJSONObject("daily").getJSONArray("temperature_2m_min").getDouble(0);
            String unit = weatherJson.getJSONObject("daily_units").getString("temperature_2m_max");

            return "Weather for " + location.getString("name") + " on " + date + ": " +
                    "Min: " + minTemp + unit + ", Max: " + maxTemp + unit;

        } catch (Exception e) {
            return "Error fetching weather data: " + e.getMessage();
        }
    }
}