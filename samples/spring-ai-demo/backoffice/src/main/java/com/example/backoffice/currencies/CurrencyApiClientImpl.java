package com.example.backoffice.currencies;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/**
 * Implementation of CurrencyApiClient that makes actual HTTP calls to external currency API.
 */
@Component
class CurrencyApiClientImpl implements CurrencyApiClient {
    private static final Logger logger = LoggerFactory.getLogger(CurrencyApiClientImpl.class);
    private final WebClient webClient;

    CurrencyApiClientImpl(WebClient.Builder webClientBuilder) {
        this.webClient = webClientBuilder
                .baseUrl("https://api.frankfurter.app")  // Changed from frankfurter.dev to frankfurter.app
                .codecs(configurer -> configurer.defaultCodecs().maxInMemorySize(1024 * 1024))
                .build();
    }

    @Override
    public Map<String, Object> getCurrencyConversionData(String fromCurrency, String toCurrency, String date) {
        // Validate currencies
        String cleanFromCurrency = fromCurrency.trim().toUpperCase();
        String cleanToCurrency = toCurrency.trim().toUpperCase();

        // Build URL - use historical rate if date provided, otherwise latest
        String url;
        if (date != null && !date.trim().isEmpty()) {
            // Validate date format
            try {
                LocalDate.parse(date.trim(), DateTimeFormatter.ISO_LOCAL_DATE);
                url = String.format("/%s?base=%s&symbols=%s",
                    date.trim(), cleanFromCurrency, cleanToCurrency);
            } catch (Exception e) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Invalid date format. Please use YYYY-MM-DD format.");
            }
        } else {
            url = String.format("/latest?base=%s&symbols=%s",
                cleanFromCurrency, cleanToCurrency);
        }

        logger.debug("Currency conversion URL: {}", url);

        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> response = webClient.get()
                    .uri(url)
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofSeconds(10))
                    .block();

            if (response == null) {
                logger.error("Failed to retrieve currency conversion data");
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "Failed to retrieve currency conversion data");
            }

            return response;
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Error calling currency service: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Error connecting to currency service: " + e.getMessage());
        }
    }

    @Override
    public Map<String, Object> getExchangeRates(String baseCurrency, String targetCurrencies) {
        String cleanBaseCurrency = baseCurrency.trim().toUpperCase();
        String url = "/latest?base=" + cleanBaseCurrency;

        // Add specific target currencies if provided
        if (targetCurrencies != null && !targetCurrencies.trim().isEmpty()) {
            String cleanTargets = targetCurrencies.trim().toUpperCase().replaceAll("\\s+", "");
            url += "&symbols=" + cleanTargets;
        }

        logger.debug("Exchange rates URL: {}", url);

        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> response = webClient.get()
                    .uri(url)
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofSeconds(10))
                    .block();

            if (response == null) {
                logger.error("Failed to retrieve exchange rates");
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "Failed to retrieve exchange rates");
            }

            return response;
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Error calling exchange rates service: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Error connecting to exchange rates service: " + e.getMessage());
        }
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, String> getSupportedCurrencies() {
        logger.debug("Getting supported currencies");

        try {
            Map<String, String> response = webClient.get()
                    .uri("/currencies")
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofSeconds(10))
                    .block();

            if (response == null) {
                logger.error("Failed to retrieve supported currencies");
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "Failed to retrieve supported currencies");
            }

            return response;
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Error calling currencies service: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Error connecting to currencies service: " + e.getMessage());
        }
    }
}
