package com.example.backoffice.currencies;

import java.util.Map;

/**
 * Interface for currency API client to abstract external API calls
 * for better testability and decoupling.
 */
interface CurrencyApiClient {

    /**
     * Get currency conversion data
     *
     * @param fromCurrency The source currency code
     * @param toCurrency The target currency code
     * @param date Optional date for historical rates (format: YYYY-MM-DD)
     * @return Map containing currency conversion response data
     */
    Map<String, Object> getCurrencyConversionData(String fromCurrency, String toCurrency, String date);

    /**
     * Get exchange rates for a base currency
     *
     * @param baseCurrency The base currency code
     * @param targetCurrencies Optional comma-separated list of target currencies
     * @return Map containing exchange rates response data
     */
    Map<String, Object> getExchangeRates(String baseCurrency, String targetCurrencies);

    /**
     * Get supported currencies
     *
     * @return Map of currency codes to currency names
     */
    Map<String, String> getSupportedCurrencies();
}
