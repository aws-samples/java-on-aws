#!/bin/bash

# Test script for Weather API endpoints using curl
source "$(dirname "$0")/test-utils.sh"

echo "Testing Weather API..."
echo "===================="

# Get dates for testing
today=$(date +%Y-%m-%d)
past_date=$(date -v-3d +%Y-%m-%d 2>/dev/null || date -d "-3 days" +%Y-%m-%d)
future_date=$(date -v+3d +%Y-%m-%d 2>/dev/null || date -d "+3 days" +%Y-%m-%d)

echo "1. Testing Current Weather (Today: $today)"
echo "========================================"

# Test weather for various cities on current date
test_endpoint "GET" "/api/weather?city=London&date=$today" 200 "Get weather for London today"
test_endpoint "GET" "/api/weather?city=Paris&date=$today" 200 "Get weather for Paris today"
test_endpoint "GET" "/api/weather?city=New%20York&date=$today" 200 "Get weather for New York today"

echo
echo "2. Testing Historical Weather (Past: $past_date)"
echo "=============================================="

# Test historical weather for various cities
test_endpoint "GET" "/api/weather?city=London&date=$past_date" 200 "Get historical weather for London"
test_endpoint "GET" "/api/weather?city=Paris&date=$past_date" 200 "Get historical weather for Paris"
test_endpoint "GET" "/api/weather?city=New%20York&date=$past_date" 200 "Get historical weather for New York"

echo
echo "3. Testing Weather Forecast (Future: $future_date)"
echo "==============================================="

# Test weather forecast for various cities
test_endpoint "GET" "/api/weather?city=London&date=$future_date" 200 "Get weather forecast for London"
test_endpoint "GET" "/api/weather?city=Paris&date=$future_date" 200 "Get weather forecast for Paris"
test_endpoint "GET" "/api/weather?city=New%20York&date=$future_date" 200 "Get weather forecast for New York"

echo
echo "4. Testing Error Handling"
echo "========================"

# Test missing required parameters - expecting failure
test_endpoint_expect_fail "GET" "/api/weather?date=$today" 400 "Get weather without city parameter"
test_endpoint_expect_fail "GET" "/api/weather?city=London" 400 "Get weather without date parameter"

# Test invalid date parameter - expecting failure
test_endpoint_expect_fail "GET" "/api/weather?city=London&date=invalid-date" 400 "Get weather with invalid date format"

# Print test summary
print_summary "Weather"
