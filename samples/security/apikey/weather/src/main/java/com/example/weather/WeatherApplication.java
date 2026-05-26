package com.example.weather;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.reactive.function.client.WebClient;

@SpringBootApplication
public class WeatherApplication {

	public static void main(String[] args) {
		SpringApplication.run(WeatherApplication.class, args);
	}

	// Spring Boot 4 no longer auto-configures WebClient.Builder.
	@Bean
	WebClient.Builder webClientBuilder() {
		return WebClient.builder();
	}

}