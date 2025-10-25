package com.example.travel.weather;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

/**
 * This class provides tool-annotated methods for AI consumption
 * while delegating actual business logic to WeatherService
 */
@Component
public class WeatherTools {
    private static final Logger logger = LoggerFactory.getLogger(WeatherTools.class);
    private final WeatherService weatherService;

    public WeatherTools(WeatherService weatherService) {
        this.weatherService = weatherService;
    }

    @Bean
    public ToolCallbackProvider weatherToolsProvider(WeatherTools weatherTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(weatherTools)
                .build();
    }

    @Tool(description = """
        Get weather forecast for a city on a specific date.
        Requires: city - Name of the city,
                 date - Date in YYYY-MM-DD format.
        Returns: Weather forecast with min/max temperatures.
        Errors: BAD_REQUEST if city is missing or date format is invalid,
               NOT_FOUND if city doesn't exist or no data for date,
               SERVICE_UNAVAILABLE if weather service is down.
        """)
    public String getWeather(String city, String date) {
        logger.info("Tool request: Getting weather for city: {} on date: {}", city, date);
        return weatherService.getWeather(city, date);
    }
}
