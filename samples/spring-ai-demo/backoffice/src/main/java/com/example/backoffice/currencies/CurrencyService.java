package com.example.backoffice.currencies;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.Map;

/**
 * Service for currency-related operations.
 * Provides methods for currency conversion and information.
 */
@Service
public class CurrencyService {
    private final CurrencyApiClient currencyApiClient;
    private static final Logger logger = LoggerFactory.getLogger(CurrencyService.class);

    CurrencyService(CurrencyApiClient currencyApiClient) {
        this.currencyApiClient = currencyApiClient;
    }

    /**
     * Converts an amount from one currency to another.
     *
     * @param fromCurrency Source currency code
     * @param toCurrency Target currency code
     * @param amount Amount to convert
     * @param date Optional historical date (YYYY-MM-DD)
     * @return Formatted conversion result with exchange rate
     */
    @Transactional(readOnly = true)
    public String convertCurrency(String fromCurrency, String toCurrency, BigDecimal amount, String date) {
        try {
            logger.debug("Converting {} {} to {} on date: {}", amount, fromCurrency, toCurrency, date);

            // Validate currencies
            String cleanFromCurrency = fromCurrency.trim().toUpperCase();
            String cleanToCurrency = toCurrency.trim().toUpperCase();

            if (cleanFromCurrency.equals(cleanToCurrency)) {
                return String.format("%.2f %s = %.2f %s (same currency)",
                    amount, cleanFromCurrency, amount, cleanToCurrency);
            }

            // Get conversion data from API client
            Map<String, Object> response = currencyApiClient.getCurrencyConversionData(
                    cleanFromCurrency, cleanToCurrency, date);

            // Extract conversion result with proper type checking
            @SuppressWarnings("unchecked")
            var rates = (Map<String, Object>) response.get("rates");
            if (rates == null || !rates.containsKey(cleanToCurrency)) {
                logger.warn("Currency conversion not available for {} to {}", cleanFromCurrency, cleanToCurrency);
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        String.format("Currency conversion not available for %s to %s. Please check currency codes.",
                                cleanFromCurrency, cleanToCurrency));
            }

            var exchangeRate = ((Number) rates.get(cleanToCurrency)).doubleValue();
            var convertedAmount = amount.doubleValue() * exchangeRate;

            var dateUsed = response.get("date");

            var result = String.format(
                "Currency Conversion (%s):\n%.2f %s = %.2f %s\nExchange Rate: 1 %s = %.6f %s",
                dateUsed, amount, cleanFromCurrency, convertedAmount, cleanToCurrency,
                cleanFromCurrency, exchangeRate, cleanToCurrency
            );

            logger.info("Successfully converted {} {} to {} {} on {}",
                amount, cleanFromCurrency, convertedAmount, cleanToCurrency, dateUsed);
            return result;

        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Error converting currency from {} to {} for amount {}: {}",
                fromCurrency, toCurrency, amount, e.getMessage(), e);
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Error converting currency: " + e.getMessage());
        }
    }

    /**
     * Gets exchange rates for a base currency.
     *
     * @param baseCurrency Base currency code
     * @param targetCurrencies Optional comma-separated list of target currencies
     * @return Formatted list of exchange rates
     */
    @Transactional(readOnly = true)
    public String getExchangeRates(String baseCurrency, String targetCurrencies) {
        try {
            logger.debug("Getting exchange rates for base currency: {} to targets: {}", baseCurrency, targetCurrencies);

            Map<String, Object> response = currencyApiClient.getExchangeRates(baseCurrency, targetCurrencies);

            @SuppressWarnings("unchecked")
            var rates = (Map<String, Object>) response.get("rates");
            var date = response.get("date");

            if (rates == null || rates.isEmpty()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        String.format("No exchange rates available for %s", baseCurrency));
            }

            StringBuilder result = new StringBuilder();
            result.append(String.format("Exchange Rates for %s (%s):\n", baseCurrency, date));

            rates.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .forEach(entry -> {
                    String currency = entry.getKey();
                    Number rate = (Number) entry.getValue();
                    result.append(String.format("1 %s = %.6f %s\n", baseCurrency, rate.doubleValue(), currency));
                });

            logger.info("Successfully retrieved {} exchange rates for {}", rates.size(), baseCurrency);
            return result.toString().trim();

        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Error getting exchange rates for {}: {}", baseCurrency, e.getMessage(), e);
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Error getting exchange rates: " + e.getMessage());
        }
    }

    /**
     * Gets a list of all supported currencies.
     *
     * @return Formatted list of currency codes and names
     */
    @Transactional(readOnly = true)
    public String getSupportedCurrencies() {
        try {
            logger.debug("Getting supported currencies");

            Map<String, String> currencies = currencyApiClient.getSupportedCurrencies();

            StringBuilder result = new StringBuilder();
            result.append("Supported Currencies:\n");

            currencies.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .forEach(entry -> {
                    String code = entry.getKey();
                    String name = entry.getValue();
                    result.append(String.format("%s - %s\n", code, name));
                });

            logger.info("Successfully retrieved {} supported currencies", currencies.size());
            return result.toString().trim();

        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            logger.error("Error getting supported currencies: {}", e.getMessage(), e);
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Error getting supported currencies: " + e.getMessage());
        }
    }
}
