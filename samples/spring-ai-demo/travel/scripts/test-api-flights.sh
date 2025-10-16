#!/bin/bash

# Test script for Flights API endpoints using curl
source "$(dirname "$0")/test-utils.sh"

echo "Testing Flights API..."
echo "===================="

echo "1. Testing Airport Endpoints"
echo "==========================="

# Test airport search endpoint
test_endpoint "GET" "/api/airports/search?city=London" 200 "Find airports by city (London)"
test_endpoint "GET" "/api/airports/search?code=LHR" 200 "Find airport by code (LHR)"

# Get an airport ID for later use
echo -e "${YELLOW}Getting airport ID from search...${NC}"
airport_search_response=$(curl -s "${BASE_URL}/api/airports/search?code=LHR")
airport_id=$(echo "$airport_search_response" | jq -r '.[0].id')

if [ -n "$airport_id" ]; then
    # Test get airport by ID
    test_endpoint "GET" "/api/airports/$airport_id" 200 "Get airport by ID"
else
    echo "Could not extract airport ID for further tests"
    ((TESTS_FAILED++))
fi

echo
echo "2. Testing Flight Endpoints"
echo "=========================="

# Test flight search
test_endpoint "GET" "/api/flights/search?departureCity=London&arrivalCity=New%20York" 200 "Find flights by route (London to New York)"
test_endpoint "GET" "/api/flights/search?flightNumber=BA102" 200 "Find flight by number (BA102)"

# First, get a real flight ID from search
echo -e "${YELLOW}Getting flight ID from search...${NC}"
flight_search_response=$(curl -s "${BASE_URL}/api/flights/search?departureCity=London&arrivalCity=New%20York")

# Extract the first flight ID and number using jq
flight_id=$(echo "$flight_search_response" | jq -r '.[0].id')
flight_number=$(echo "$flight_search_response" | jq -r '.[0].flightNumber')

if [ -n "$flight_id" ]; then
    # Test get flight by ID
    test_endpoint "GET" "/api/flights/$flight_id" 200 "Get flight by ID"
else
    echo "Could not extract flight ID for further tests"
    ((TESTS_FAILED++))
fi

echo
echo "3. Testing Flight Booking Flow"
echo "============================="

if [ -z "$flight_id" ]; then
    echo -e "${RED}Failed to get flight ID from search results${NC}"
    exit 1
fi

echo "Using flight: $flight_number (ID: $flight_id)"

# Create a JSON payload for the booking
booking_payload=$(cat <<EOF
{
  "flightId": "$flight_id",
  "flightDate": "2025-08-15",
  "customerName": "John Doe",
  "customerEmail": "john.doe@example.com",
  "numberOfPassengers": 2
}
EOF
)

# Test create flight booking with POST and JSON payload
echo -e "${YELLOW}Testing:${NC} Create flight booking"
echo "Request: POST ${BASE_URL}/api/flight-bookings"
echo "Payload: $booking_payload"

booking_response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/flight-bookings" \
  -H "Content-Type: application/json" \
  -d "$booking_payload")

booking_status=$(echo "$booking_response" | tail -n1)
booking_body=$(echo "$booking_response" | sed '$d')

echo "Response Status: $booking_status"
echo "Response Body: $booking_body"

if [ "$booking_status" -eq 201 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Create flight booking"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Create flight booking (Expected: 201, Got: $booking_status)"
    ((TESTS_FAILED++))
fi
echo "----------------------------------------"

# Extract the booking reference and ID using jq
booking_reference=$(echo "$booking_body" | jq -r '.bookingReference')
booking_id=$(echo "$booking_body" | jq -r '.id')

if [ -n "$booking_reference" ]; then
    echo "Created booking reference: $booking_reference (ID: $booking_id)"

    # Test search booking by reference
    test_endpoint "GET" "/api/flight-bookings/search?bookingReference=$booking_reference" 200 "Search flight booking by reference"

    # Test get booking by ID
    test_endpoint "GET" "/api/flight-bookings/$booking_id" 200 "Get flight booking by ID"

    # Test confirm booking
    confirm_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/flight-bookings/$booking_reference/confirm")
    confirm_status=$(echo "$confirm_response" | tail -n1)
    confirm_body=$(echo "$confirm_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Confirm flight booking"
    echo "Request: PUT ${BASE_URL}/api/flight-bookings/$booking_reference/confirm"
    echo "Response Status: $confirm_status"
    echo "Response Body: $confirm_body"

    if [ "$confirm_status" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Confirm flight booking"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Confirm flight booking (Expected: 200, Got: $confirm_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"

    # Test cancel booking
    cancel_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/flight-bookings/$booking_reference/cancel")
    cancel_status=$(echo "$cancel_response" | tail -n1)
    cancel_body=$(echo "$cancel_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Cancel flight booking"
    echo "Request: PUT ${BASE_URL}/api/flight-bookings/$booking_reference/cancel"
    echo "Response Status: $cancel_status"
    echo "Response Body: $cancel_body"

    if [ "$cancel_status" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Cancel flight booking"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Cancel flight booking (Expected: 200, Got: $cancel_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"
else
    echo "Could not extract booking reference for further tests"
    ((TESTS_FAILED+=4))  # Count the skipped tests as failures
fi

echo
echo "4. Testing Error Handling"
echo "========================"

# Test non-existent flight
test_endpoint_expect_fail "GET" "/api/flights/00000000-0000-0000-0000-000000000000" 404 "Get non-existent flight by ID"

# Test booking with invalid flight ID
invalid_booking_payload=$(cat <<EOF
{
  "flightId": "00000000-0000-0000-0000-000000000000",
  "flightDate": "2025-08-15",
  "customerName": "John Doe",
  "customerEmail": "john.doe@example.com",
  "numberOfPassengers": 1
}
EOF
)

echo -e "${YELLOW}Testing:${NC} Create booking with invalid flight ID"
echo "Request: POST ${BASE_URL}/api/flight-bookings"
echo "Payload: $invalid_booking_payload"

invalid_booking_response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/flight-bookings" \
  -H "Content-Type: application/json" \
  -d "$invalid_booking_payload")

invalid_booking_status=$(echo "$invalid_booking_response" | tail -n1)
invalid_booking_body=$(echo "$invalid_booking_response" | sed '$d')

echo "Response Status: $invalid_booking_status"
echo "Response Body: $invalid_booking_body"

if [ "$invalid_booking_status" -eq 404 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Create booking with invalid flight ID (Expected error)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Create booking with invalid flight ID (Expected: 404, Got: $invalid_booking_status)"
    ((TESTS_FAILED++))
fi
echo "----------------------------------------"

# Print test summary
print_summary "Flights"
