#!/bin/bash

# Common utilities for API testing
# This script provides shared functions for all API test scripts

# Colors for output
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Default base URL
export BASE_URL=${BASE_URL:-"http://localhost:8082"}

# Initialize counters
export TESTS_PASSED=0
export TESTS_FAILED=0

# Function to test an endpoint and check the status code
test_endpoint() {
    local method=$1
    local endpoint=$2
    local expected_status=$3
    local description=$4
    local data=$5

    echo -e "${YELLOW}Testing:${NC} $description"
    echo "Request: $method ${BASE_URL}${endpoint}"

    # Execute the request with curl
    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${BASE_URL}${endpoint}")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method "${BASE_URL}${endpoint}")
    fi

    # Extract HTTP status code (last line)
    status_code=$(echo "$response" | tail -n1)
    # Extract response body (all but last line)
    body=$(echo "$response" | sed '$d')

    echo "Response Status: $status_code"
    if [ ${#body} -gt 500 ]; then
        echo "Response Body: ${body:0:500}... (truncated)"
    else
        echo "Response Body: $body"
    fi

    # Check if the status code matches the expected status
    if [ "$status_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description (Expected: $expected_status, Got: $status_code)"
        ((TESTS_FAILED++))
    fi

    echo "----------------------------------------"

    # Return the response body for further processing if needed
    echo "$body"
}

# Function to test an endpoint that is expected to fail
test_endpoint_expect_fail() {
    local method=$1
    local endpoint=$2
    local expected_status=$3
    local description=$4
    local data=$5

    echo -e "${YELLOW}Testing:${NC} $description"
    echo "Request: $method ${BASE_URL}${endpoint} (expected to fail)"

    # Execute the request with curl
    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${BASE_URL}${endpoint}")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method "${BASE_URL}${endpoint}")
    fi

    # Extract HTTP status code (last line)
    status_code=$(echo "$response" | tail -n1)
    # Extract response body (all but last line)
    body=$(echo "$response" | sed '$d')

    echo "Response Status: $status_code"
    if [ ${#body} -gt 500 ]; then
        echo "Response Body: ${body:0:500}... (truncated)"
    else
        echo "Response Body: $body"
    fi

    # Check if the status code is 4xx or 5xx (client or server error)
    if [[ "$status_code" =~ ^[45][0-9][0-9]$ ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description (failed as expected with HTTP $status_code)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description (should have failed, but got HTTP $status_code)"
        ((TESTS_FAILED++))
    fi

    echo "----------------------------------------"
}

# Function to print test summary
print_summary() {
    local api_name=$1

    echo
    echo "=== $api_name API Test Summary ==="
    echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
    echo "Total tests: $((TESTS_PASSED + TESTS_FAILED))"
}
