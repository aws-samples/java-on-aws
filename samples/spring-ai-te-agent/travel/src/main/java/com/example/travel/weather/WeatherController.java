package com.example.travel.weather;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("api/weather")
class WeatherController {
    private final WeatherService weatherService;
    private static final Logger logger = LoggerFactory.getLogger(WeatherController.class);

    WeatherController(WeatherService weatherService) {
        this.weatherService = weatherService;
    }

    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    String getWeather(@RequestParam String city, @RequestParam String date) {
        logger.info("Getting weather for city: {} on date: {}", city, date);
        return weatherService.getWeather(city, date);
    }
}
