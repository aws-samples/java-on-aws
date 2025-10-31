package com.example.weather;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("api/weather")
public class WeatherController {
    private final WeatherService weatherService;
    private static final Logger logger = LoggerFactory.getLogger(WeatherController.class);

    public WeatherController(WeatherService weatherService) {
        this.weatherService = weatherService;
    }

    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    public String getWeather(@RequestParam String city, @RequestParam String date) {
        logger.info("Getting weather for city: {} on date: {}", city, date);
        return weatherService.getWeather(city, date);
    }
}