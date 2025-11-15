package com.example.weather;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springaicommunity.mcp.annotation.McpTool;
import org.springframework.security.access.prepost.PreAuthorize;
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

//    @Bean
//    public ToolCallbackProvider weatherToolsProvider() {
//        return MethodToolCallbackProvider.builder()
//                .toolObjects(this)
//                .build();
//    }

    @PreAuthorize("isAuthenticated()")
//    @Tool(description = """
//        Get weather forecast for a city on a specific date.
//        Requires: city - Name of the city,
//                 date - Date in YYYY-MM-DD format.
//        Returns: Weather forecast with min/max temperatures.
//        Errors: BAD_REQUEST if city is missing or date format is invalid,
//               NOT_FOUND if city doesn't exist or no data for date,
//               SERVICE_UNAVAILABLE if weather service is down.
//        """)
    @McpTool(description = """
        Get weather forecast for a city on a specific date.
        Requires: city - Name of the city,
                 date - Date in YYYY-MM-DD format.
        Returns: Weather forecast with min/max temperatures.
        Errors: BAD_REQUEST if city is missing or date format is invalid,
               NOT_FOUND if city doesn't exist or no data for date,
               SERVICE_UNAVAILABLE if weather service is down.
        """)
    public String getWeatherForecast(String city, String date) {
        logger.info("Tool request: Getting weather for city: {} on date: {}", city, date);
        return weatherService.getWeather(city, date);
    }
}