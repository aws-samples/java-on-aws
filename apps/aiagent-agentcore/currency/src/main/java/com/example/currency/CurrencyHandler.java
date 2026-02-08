package com.example.currency;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.google.gson.Gson;
import com.google.gson.JsonObject;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

/**
 * AWS Lambda handler for currency conversion tools.
 * Calls Frankfurter API for real-time exchange rates.
 */
public class CurrencyHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String FRANKFURTER_API = "https://api.frankfurter.app";
    private static final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
    private static final Gson gson = new Gson();

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        // Log full input for debugging
        context.getLogger().log("Full input: " + gson.toJson(input));

        // Gateway sends arguments directly, not wrapped in {name, arguments}
        // Detect tool from input structure:
        // - convertCurrency: has fromCurrency, toCurrency, amount
        // - getSupportedCurrencies: empty or no currency-related fields
        String toolName;
        Map<String, Object> arguments;

        if (input.containsKey("name") && input.containsKey("arguments")) {
            // Direct invocation format: {name: "...", arguments: {...}}
            toolName = (String) input.get("name");
            if (toolName != null && toolName.contains("___")) {
                toolName = toolName.substring(toolName.indexOf("___") + 3);
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> args = (Map<String, Object>) input.getOrDefault("arguments", Map.of());
            arguments = args;
        } else if (input.containsKey("fromCurrency") || input.containsKey("toCurrency") || input.containsKey("amount")) {
            // Gateway format for convertCurrency: arguments sent directly
            toolName = "convertCurrency";
            arguments = input;
        } else {
            // Gateway format for getSupportedCurrencies: empty or minimal input
            toolName = "getSupportedCurrencies";
            arguments = input;
        }

        context.getLogger().log("Tool: " + toolName + ", Arguments: " + arguments);

        try {
            return switch (toolName) {
                case "convertCurrency" -> convertCurrency(arguments);
                case "getSupportedCurrencies" -> getSupportedCurrencies();
                default -> Map.of("error", "Unknown tool: " + toolName);
            };
        } catch (Exception e) {
            context.getLogger().log("Error: " + e.getMessage());
            return Map.of("error", e.getMessage());
        }
    }

    private Map<String, Object> convertCurrency(Map<String, Object> args) throws Exception {
        String from = ((String) args.get("fromCurrency")).toUpperCase().trim();
        String to = ((String) args.get("toCurrency")).toUpperCase().trim();
        double amount = ((Number) args.get("amount")).doubleValue();

        if (from.equals(to)) {
            return Map.of("result", String.format("%.2f %s = %.2f %s (same currency)", amount, from, amount, to));
        }

        String url = String.format("%s/latest?base=%s&symbols=%s", FRANKFURTER_API, from, to);
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofSeconds(10))
                .GET()
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            return Map.of("error", "Currency API error: " + response.body());
        }

        JsonObject json = gson.fromJson(response.body(), JsonObject.class);
        JsonObject rates = json.getAsJsonObject("rates");
        double rate = rates.get(to).getAsDouble();
        double converted = amount * rate;
        String date = json.get("date").getAsString();

        String result = String.format(
                "%.2f %s = %.2f %s (rate: %.6f, date: %s)",
                amount, from, converted, to, rate, date
        );

        return Map.of("result", result);
    }

    private Map<String, Object> getSupportedCurrencies() throws Exception {
        String url = FRANKFURTER_API + "/currencies";
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofSeconds(10))
                .GET()
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            return Map.of("error", "Currency API error: " + response.body());
        }

        @SuppressWarnings("unchecked")
        Map<String, String> currencies = gson.fromJson(response.body(), Map.class);

        StringBuilder sb = new StringBuilder("Supported currencies:\n");
        currencies.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .forEach(e -> sb.append(String.format("- %s: %s\n", e.getKey(), e.getValue())));

        return Map.of("result", sb.toString().trim());
    }
}
