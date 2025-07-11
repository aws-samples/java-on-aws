package com.example.backoffice.currencies;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;

/**
 * REST controller for currency-related endpoints.
 * Provides API for currency conversion and information.
 */
@RestController
@RequestMapping("api/currencies")
class CurrencyController {
    private final CurrencyService currencyService;
    private static final Logger logger = LoggerFactory.getLogger(CurrencyController.class);

    CurrencyController(CurrencyService currencyService) {
        this.currencyService = currencyService;
    }

    /**
     * Unified search endpoint for currency operations.
     * Supports conversion, exchange rates, and listing supported currencies.
     */
    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    public String search(
            @RequestParam(required = false) String fromCurrency,
            @RequestParam(required = false) String toCurrency,
            @RequestParam(required = false) BigDecimal amount,
            @RequestParam(required = false) String date,
            @RequestParam(required = false) String baseCurrency,
            @RequestParam(required = false) String targetCurrencies,
            @RequestParam(required = false) Boolean listCurrencies) {

        try {
            // Currency conversion
            if (fromCurrency != null && toCurrency != null && amount != null) {
                logger.debug("Search: Converting {} {} to {}", amount, fromCurrency, toCurrency);
                return currencyService.convertCurrency(fromCurrency, toCurrency, amount, date);
            }

            // Exchange rates
            if (baseCurrency != null) {
                logger.debug("Search: Getting exchange rates for {}", baseCurrency);
                return currencyService.getExchangeRates(baseCurrency, targetCurrencies);
            }

            // List supported currencies
            if (Boolean.TRUE.equals(listCurrencies)) {
                logger.debug("Search: Listing supported currencies");
                return currencyService.getSupportedCurrencies();
            }

            // No valid parameters provided
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Please provide valid search parameters: either (fromCurrency, toCurrency, amount) " +
                    "for conversion, baseCurrency for exchange rates, or listCurrencies=true to list currencies");

        } catch (Exception e) {
            logger.error("Error in currency search: {}", e.getMessage(), e);
            throw e;
        }
    }

    /**
     * Convert currency amounts.
     */
    @GetMapping("/convert")
    @ResponseStatus(HttpStatus.OK)
    public String convertCurrency(
            @RequestParam String fromCurrency,
            @RequestParam String toCurrency,
            @RequestParam BigDecimal amount,
            @RequestParam(required = false) String date) {

        logger.debug("Converting {} {} to {} on date: {}", amount, fromCurrency, toCurrency, date);
        try {
            return currencyService.convertCurrency(fromCurrency, toCurrency, amount, date);
        } catch (Exception e) {
            logger.error("Error converting currency: {}", e.getMessage(), e);
            throw e;
        }
    }

    /**
     * Get exchange rates for a base currency.
     */
    @GetMapping("/rates")
    @ResponseStatus(HttpStatus.OK)
    public String getExchangeRates(
            @RequestParam String baseCurrency,
            @RequestParam(required = false) String targetCurrencies) {

        logger.debug("Getting exchange rates for {} to {}", baseCurrency, targetCurrencies);
        try {
            return currencyService.getExchangeRates(baseCurrency, targetCurrencies);
        } catch (Exception e) {
            logger.error("Error getting exchange rates: {}", e.getMessage(), e);
            throw e;
        }
    }

    /**
     * Get a list of all supported currencies.
     */
    @GetMapping("/currencies")
    @ResponseStatus(HttpStatus.OK)
    public String getSupportedCurrencies() {
        logger.debug("Getting supported currencies");
        try {
            return currencyService.getSupportedCurrencies();
        } catch (Exception e) {
            logger.error("Error getting supported currencies: {}", e.getMessage(), e);
            throw e;
        }
    }
}
