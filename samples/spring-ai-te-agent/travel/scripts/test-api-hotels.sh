#!/bin/bash

# Test script for Hotels API endpoints using curl
source "$(dirname "$0")/test-utils.sh"

echo "Testing Hotels API..."
echo "===================="

echo "1. Testing Hotel Search"
echo "======================="

# Test hotel search with unified search endpoint
test_endpoint "GET" "/api/hotels/search?city=Madrid&checkInDate=2025-07-15&numberOfNights=3" 200 "Find hotels in Madrid"
test_endpoint "GET" "/api/hotels/search?city=Paris&checkInDate=2025-07-20&numberOfNights=4" 200 "Find hotels in Paris"
test_endpoint "GET" "/api/hotels/search?name=Marriott" 200 "Find hotels by name (Marriott)"

# First, get a real hotel from Paris search
echo -e "${YELLOW}Getting hotel from Paris search...${NC}"
paris_hotels_response=$(curl -s "${BASE_URL}/api/hotels/search?city=Paris&checkInDate=2025-07-20&numberOfNights=4")

# Extract the first hotel ID and name using jq
hotel_id=$(echo "$paris_hotels_response" | jq -r '.[0].id')
hotel_name=$(echo "$paris_hotels_response" | jq -r '.[0].hotelName')

if [ -z "$hotel_id" ]; then
    echo -e "${RED}Failed to get hotel ID from search results${NC}"
    exit 1
fi

echo "Using hotel: $hotel_name (ID: $hotel_id)"

# Test get hotel by ID
test_endpoint "GET" "/api/hotels/$hotel_id" 200 "Get hotel by ID"

echo
echo "2. Testing Hotel Booking Flow"
echo "============================"

# Create a JSON payload for the booking
booking_payload=$(cat <<EOF
{
  "hotelId": "$hotel_id",
  "customerName": "Jane Smith",
  "customerEmail": "jane.smith@example.com",
  "checkInDate": "2025-07-20",
  "checkOutDate": "2025-07-24",
  "numberOfGuests": 2,
  "numberOfRooms": 1
}
EOF
)

# Test create hotel booking with POST and JSON payload
echo -e "${YELLOW}Testing:${NC} Create hotel booking"
echo "Request: POST ${BASE_URL}/api/hotel-bookings"
echo "Payload: $booking_payload"

booking_response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/hotel-bookings" \
  -H "Content-Type: application/json" \
  -d "$booking_payload")

booking_status=$(echo "$booking_response" | tail -n1)
booking_body=$(echo "$booking_response" | sed '$d')

echo "Response Status: $booking_status"
echo "Response Body: $booking_body"

if [ "$booking_status" -eq 201 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Create hotel booking"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Create hotel booking (Expected: 201, Got: $booking_status)"
    ((TESTS_FAILED++))
fi
echo "----------------------------------------"

# Extract the booking reference and ID using jq
booking_reference=$(echo "$booking_body" | jq -r '.bookingReference')
booking_id=$(echo "$booking_body" | jq -r '.id')

if [ -n "$booking_reference" ]; then
    echo "Created booking reference: $booking_reference (ID: $booking_id)"

    # Test search booking by reference
    test_endpoint "GET" "/api/hotel-bookings/search?bookingReference=$booking_reference" 200 "Search booking by reference"

    # Test get booking by ID
    test_endpoint "GET" "/api/hotel-bookings/$booking_id" 200 "Get booking by ID"

    # Test update booking
    update_payload=$(cat <<EOF
{
  "id": "$booking_id",
  "bookingReference": "$booking_reference",
  "hotelId": "$hotel_id",
  "customerName": "Jane Smith Updated",
  "customerEmail": "jane.updated@example.com",
  "checkInDate": "2025-07-21",
  "checkOutDate": "2025-07-25",
  "numberOfGuests": 3,
  "numberOfRooms": 1
}
EOF
)

    echo -e "${YELLOW}Testing:${NC} Update hotel booking"
    echo "Request: PUT ${BASE_URL}/api/hotel-bookings/$booking_reference"
    echo "Payload: $update_payload"

    update_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/hotel-bookings/$booking_reference" \
      -H "Content-Type: application/json" \
      -d "$update_payload")

    update_status=$(echo "$update_response" | tail -n1)
    update_body=$(echo "$update_response" | sed '$d')

    echo "Response Status: $update_status"
    echo "Response Body: $update_body"

    if [ "$update_status" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Update hotel booking"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Update hotel booking (Expected: 200, Got: $update_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"

    # Test confirm booking
    confirm_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/hotel-bookings/$booking_reference/confirm")
    confirm_status=$(echo "$confirm_response" | tail -n1)
    confirm_body=$(echo "$confirm_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Confirm hotel booking"
    echo "Request: PUT ${BASE_URL}/api/hotel-bookings/$booking_reference/confirm"
    echo "Response Status: $confirm_status"
    echo "Response Body: $confirm_body"

    if [ "$confirm_status" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Confirm hotel booking"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Confirm hotel booking (Expected: 200, Got: $confirm_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"

    # Test cancel booking
    cancel_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/hotel-bookings/$booking_reference/cancel")
    cancel_status=$(echo "$cancel_response" | tail -n1)
    cancel_body=$(echo "$cancel_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Cancel hotel booking"
    echo "Request: PUT ${BASE_URL}/api/hotel-bookings/$booking_reference/cancel"
    echo "Response Status: $cancel_status"
    echo "Response Body: $cancel_body"

    if [ "$cancel_status" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Cancel hotel booking"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Cancel hotel booking (Expected: 200, Got: $cancel_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"
else
    echo "Could not extract booking reference for further tests"
    ((TESTS_FAILED+=4))  # Count the skipped tests as failures
fi

echo
echo "3. Testing Error Handling"
echo "========================="

# Test missing required parameters - expecting empty list, not failure
test_endpoint "GET" "/api/hotels/search?city=Paris" 200 "Search hotels with partial parameters (should return empty list)"

# Test non-existent hotel booking - expecting empty list, not failure
test_endpoint "GET" "/api/hotel-bookings/search?bookingReference=NONEXIST" 200 "Search non-existent hotel booking (should return empty list)"

# Test booking with invalid hotel ID - expecting failure
invalid_booking_payload=$(cat <<EOF
{
  "hotelId": "00000000-0000-0000-0000-000000000000",
  "customerName": "John Doe",
  "customerEmail": "john@example.com",
  "checkInDate": "2025-08-20",
  "checkOutDate": "2025-08-22",
  "numberOfGuests": 1,
  "numberOfRooms": 1
}
EOF
)

echo -e "${YELLOW}Testing:${NC} Create booking with invalid hotel ID"
echo "Request: POST ${BASE_URL}/api/hotel-bookings"
echo "Payload: $invalid_booking_payload"

invalid_booking_response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/hotel-bookings" \
  -H "Content-Type: application/json" \
  -d "$invalid_booking_payload")

invalid_booking_status=$(echo "$invalid_booking_response" | tail -n1)
invalid_booking_body=$(echo "$invalid_booking_response" | sed '$d')

echo "Response Status: $invalid_booking_status"
echo "Response Body: $invalid_booking_body"

if [ "$invalid_booking_status" -eq 404 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Create booking with invalid hotel ID (Expected error)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Create booking with invalid hotel ID (Expected: 404, Got: $invalid_booking_status)"
    ((TESTS_FAILED++))
fi
echo "----------------------------------------"

# Print test summary
print_summary "Hotels"
