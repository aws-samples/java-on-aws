#!/bin/bash

# Test script for Currency API endpoints using curl
source "$(dirname "$0")/test-utils.sh"

echo "Testing Currencies API..."
echo "======================"

# Get dates for testing
today=$(date +%Y-%m-%d)
past_date=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "-30 days" +%Y-%m-%d)

echo "1. Testing Currency Conversion"
echo "============================="

# Test currency conversion with various currencies using the unified search endpoint
test_endpoint "GET" "/api/currencies/search?fromCurrency=USD&toCurrency=EUR&amount=100" 200 "Convert USD to EUR (unified search)"
test_endpoint "GET" "/api/currencies/search?fromCurrency=EUR&toCurrency=GBP&amount=50" 200 "Convert EUR to GBP (unified search)"
test_endpoint "GET" "/api/currencies/search?fromCurrency=GBP&toCurrency=JPY&amount=75" 200 "Convert GBP to JPY (unified search)"

# Test with the direct endpoint
test_endpoint "GET" "/api/currencies/convert?fromCurrency=USD&toCurrency=EUR&amount=100" 200 "Convert USD to EUR (direct endpoint)"

echo
echo "2. Testing Historical Conversion"
echo "==============================="

# Test historical currency conversion with unified search endpoint
test_endpoint "GET" "/api/currencies/search?fromCurrency=USD&toCurrency=EUR&amount=100&date=$past_date" 200 "Convert USD to EUR on past date (unified search)"

# Test with the direct endpoint
test_endpoint "GET" "/api/currencies/convert?fromCurrency=EUR&toCurrency=GBP&amount=50&date=$past_date" 200 "Convert EUR to GBP on past date (direct endpoint)"

echo
echo "3. Testing Exchange Rates"
echo "========================"

# Test getting exchange rates with unified search endpoint
test_endpoint "GET" "/api/currencies/search?baseCurrency=USD" 200 "Get exchange rates with USD base (unified search)"
test_endpoint "GET" "/api/currencies/search?baseCurrency=EUR" 200 "Get exchange rates with EUR base (unified search)"

# Test with the direct endpoint
test_endpoint "GET" "/api/currencies/rates?baseCurrency=USD&targetCurrencies=EUR,GBP,JPY" 200 "Get specific exchange rates with USD base (direct endpoint)"

echo
echo "4. Testing Supported Currencies"
echo "=============================="

# Test getting supported currencies with unified search endpoint
test_endpoint "GET" "/api/currencies/search?listCurrencies=true" 200 "Get supported currencies (unified search)"

# Test with the direct endpoint
test_endpoint "GET" "/api/currencies/currencies" 200 "Get supported currencies (direct endpoint)"

echo
echo "5. Testing Error Handling"
echo "========================"

# Test missing required parameters with unified search endpoint - expecting failure
test_endpoint_expect_fail "GET" "/api/currencies/search?toCurrency=EUR&amount=100" 400 "Convert without fromCurrency parameter"
test_endpoint_expect_fail "GET" "/api/currencies/search?fromCurrency=USD&amount=100" 400 "Convert without toCurrency parameter"
test_endpoint_expect_fail "GET" "/api/currencies/search?fromCurrency=USD&toCurrency=EUR" 400 "Convert without amount parameter"

# Test with the direct endpoint
test_endpoint_expect_fail "GET" "/api/currencies/convert?toCurrency=EUR&amount=100" 400 "Convert without fromCurrency parameter (direct)"
test_endpoint_expect_fail "GET" "/api/currencies/convert?fromCurrency=USD&amount=100" 400 "Convert without toCurrency parameter (direct)"
test_endpoint_expect_fail "GET" "/api/currencies/convert?fromCurrency=USD&toCurrency=EUR" 400 "Convert without amount parameter (direct)"

# Test invalid parameters - expecting failure
test_endpoint_expect_fail "GET" "/api/currencies/search?fromCurrency=INVALID&toCurrency=EUR&amount=100" 400 "Convert with invalid fromCurrency"
test_endpoint_expect_fail "GET" "/api/currencies/search?fromCurrency=USD&toCurrency=INVALID&amount=100" 400 "Convert with invalid toCurrency"
test_endpoint_expect_fail "GET" "/api/currencies/search?fromCurrency=USD&toCurrency=EUR&amount=100&date=invalid-date" 400 "Convert with invalid date format"

# Test same currency conversion - should work but return same amount
test_endpoint "GET" "/api/currencies/search?fromCurrency=USD&toCurrency=USD&amount=100" 200 "Convert USD to USD (same currency)"

echo
echo "6. Testing Integration with Expenses"
echo "=================================="

# Create an expense with EUR currency and no amountEur
expense_eur='{
  "documentType": "RECEIPT",
  "expenseType": "OFFICE_SUPPLIES",
  "amountOriginal": 45.80,
  "currency": "EUR",
  "date": "2025-07-01",
  "userId": "testuser",
  "expenseStatus": "DRAFT",
  "description": "Office supplies in EUR"
}'

test_endpoint "POST" "/api/expenses" 201 "Create expense with EUR currency" "$expense_eur"

# Create an expense with non-EUR currency and amountEur provided
expense_with_eur='{
  "documentType": "RECEIPT",
  "expenseType": "MEALS",
  "amountOriginal": 100.00,
  "amountEur": 85.50,
  "currency": "USD",
  "date": "2025-07-01",
  "userId": "testuser",
  "expenseStatus": "DRAFT",
  "description": "Business lunch with EUR amount provided"
}'

test_endpoint "POST" "/api/expenses" 201 "Create expense with amountEur provided" "$expense_with_eur"

# Print test summary
print_summary "Currency"
