package com.example.backoffice.currencies;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;

/**
 * Tools class for AI-assisted currency operations.
 * Separates tool-annotated methods from the service layer.
 */
@Component
public class CurrencyTools {
    private final CurrencyService currencyService;
    private static final Logger logger = LoggerFactory.getLogger(CurrencyTools.class);

    public CurrencyTools(CurrencyService currencyService) {
        this.currencyService = currencyService;
    }

    @Bean
    public ToolCallbackProvider currencyToolsProvider(CurrencyTools currencyTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(currencyTools)
                .build();
    }

    @Tool(description = """
        Convert currency amounts using real exchange rates.
        Requires: fromCurrency - Source currency code, toCurrency - Target currency code,
        amount - Amount to convert, date - Optional historical date (YYYY-MM-DD).
        Returns: Formatted conversion result with exchange rate.
        Errors: BAD_REQUEST if currency codes are invalid, SERVICE_UNAVAILABLE if API is down.
        """)
    public String convertCurrency(String fromCurrency, String toCurrency, BigDecimal amount, String date) {
        logger.debug("Tool: Converting {} {} to {} on date: {}", amount, fromCurrency, toCurrency, date);
        return currencyService.convertCurrency(fromCurrency, toCurrency, amount, date);
    }

    @Tool(description = """
        Get a list of all supported currencies.
        Returns: Formatted list of currency codes and names.
        Errors: SERVICE_UNAVAILABLE if API is down.
        """)
    public String getSupportedCurrencies() {
        logger.debug("Tool: Getting supported currencies");
        return currencyService.getSupportedCurrencies();
    }
}
