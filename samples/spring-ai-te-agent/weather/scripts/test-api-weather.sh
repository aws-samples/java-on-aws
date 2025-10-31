#!/bin/bash

# Test script for Weather API endpoints using curl
source "$(dirname "$0")/test-utils.sh"

echo "Testing Weather API..."
echo "===================="

# Get dates for testing
today=$(date +%Y-%m-%d)
past_date=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "-30 days" +%Y-%m-%d)
future_date=$(date -v+7d +%Y-%m-%d 2>/dev/null || date -d "+7 days" +%Y-%m-%d)

echo "1. Testing Weather Forecast - Current Date"
echo "=========================================="

# Test weather forecast for various cities on current date
test_endpoint "GET" "/api/weather?city=London&date=$today" 200 "Get weather for London (current date)"
test_endpoint "GET" "/api/weather?city=New%20York&date=$today" 200 "Get weather for New York (current date)"
test_endpoint "GET" "/api/weather?city=Tokyo&date=$today" 200 "Get weather for Tokyo (current date)"
test_endpoint "GET" "/api/weather?city=Paris&date=$today" 200 "Get weather for Paris (current date)"

echo
echo "2. Testing Weather Forecast - Historical Data"
echo "============================================="

# Test weather forecast for past dates
test_endpoint "GET" "/api/weather?city=London&date=$past_date" 200 "Get weather for London (past date)"
test_endpoint "GET" "/api/weather?city=Berlin&date=$past_date" 200 "Get weather for Berlin (past date)"
test_endpoint "GET" "/api/weather?city=Madrid&date=$past_date" 200 "Get weather for Madrid (past date)"

echo
echo "3. Testing Weather Forecast - Future Data"
echo "========================================="

# Test weather forecast for future dates (within API limitations)
test_endpoint "GET" "/api/weather?city=Rome&date=$future_date" 200 "Get weather for Rome (7 days future)"
test_endpoint "GET" "/api/weather?city=Amsterdam&date=$future_date" 200 "Get weather for Amsterdam (7 days future)"

echo
echo "4. Testing International Cities"
echo "=============================="

# Test weather for international cities using commonly recognized names
test_endpoint "GET" "/api/weather?city=Sao%20Paulo&date=$today" 200 "Get weather for Sao Paulo (without accent)"
test_endpoint "GET" "/api/weather?city=Munich&date=$today" 200 "Get weather for Munich (English name)"
test_endpoint "GET" "/api/weather?city=Beijing&date=$today" 200 "Get weather for Beijing (English name)"

echo
echo "5. Testing Error Handling"
echo "========================"

# Test missing required parameters - expecting failure
test_endpoint_expect_fail "GET" "/api/weather?date=$today" 400 "Get weather without city parameter"
test_endpoint_expect_fail "GET" "/api/weather?city=London" 400 "Get weather without date parameter"

# Test invalid parameters - expecting failure
test_endpoint_expect_fail "GET" "/api/weather?city=London&date=invalid-date" 400 "Get weather with invalid date format"
test_endpoint_expect_fail "GET" "/api/weather?city=NonExistentCity123&date=$today" 404 "Get weather for non-existent city"

# Test empty parameters - expecting failure
test_endpoint_expect_fail "GET" "/api/weather?city=&date=$today" 400 "Get weather with empty city parameter"

echo
echo "6. Testing Edge Cases"
echo "===================="

# Test cities with spaces and special characters in URL encoding
test_endpoint "GET" "/api/weather?city=Los%20Angeles&date=$today" 200 "Get weather for Los Angeles (URL encoded)"
test_endpoint "GET" "/api/weather?city=New%20Delhi&date=$today" 200 "Get weather for New Delhi (URL encoded)"

# Test very long city names
test_endpoint_expect_fail "GET" "/api/weather?city=ThisIsAVeryLongCityNameThatProbablyDoesNotExistAnywhere&date=$today" 404 "Get weather for very long city name"

# Test date boundaries (far future - expected to fail due to API limitations)
far_future_date="2030-01-01"
test_endpoint_expect_fail "GET" "/api/weather?city=London&date=$far_future_date" 503 "Get weather for far future date (API limitation)"

# Print test summary
print_summary "Weather"