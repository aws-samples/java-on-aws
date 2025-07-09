#!/bin/bash

# Comprehensive test script for Expenses API endpoints
source "$(dirname "$0")/test-utils.sh"

echo "Testing Expenses API..."
echo "======================"

echo "1. Testing Expense Creation"
echo "=========================="

# Create an expense with all required fields
valid_expense='{
  "documentType": "RECEIPT",
  "expenseType": "MEALS",
  "amountOriginal": 25.50,
  "amountEur": 21.75,
  "currency": "USD",
  "date": "2025-06-30",
  "userId": "user123",
  "expenseStatus": "DRAFT",
  "description": "Business lunch",
  "expenseDetails": "Lunch with client"
}'

# Use curl directly to create expense and extract ID
create_response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/expenses" \
  -H "Content-Type: application/json" \
  -d "$valid_expense")
create_status=$(echo "$create_response" | tail -n1)
create_body=$(echo "$create_response" | sed '$d')

echo -e "${YELLOW}Testing:${NC} Create a valid expense"
echo "Request: POST ${BASE_URL}/api/expenses"
echo "Response Status: $create_status"
echo "Response Body: $create_body"

if [ "$create_status" -eq 201 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Create a valid expense"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Create a valid expense (Expected: 201, Got: $create_status)"
    ((TESTS_FAILED++))
fi
echo "----------------------------------------"

# Extract expense ID using grep and cut
expense_id=$(echo "$create_body" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "Created expense with ID: $expense_id"

# Extract expense reference using grep and cut
expense_reference=$(echo "$create_body" | grep -o '"expenseReference":"[^"]*"' | cut -d'"' -f4)
echo "Created expense with reference: $expense_reference"

# Create an expense without amountEur (should be null)
expense_no_eur='{
  "documentType": "INVOICE",
  "expenseType": "TRANSPORTATION",
  "amountOriginal": 45.00,
  "currency": "GBP",
  "date": "2025-07-01",
  "userId": "user456",
  "expenseStatus": "DRAFT",
  "description": "Taxi fare"
}'

# Use curl directly to create second expense and extract ID
create_response2=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/expenses" \
  -H "Content-Type: application/json" \
  -d "$expense_no_eur")
create_status2=$(echo "$create_response2" | tail -n1)
create_body2=$(echo "$create_response2" | sed '$d')

echo -e "${YELLOW}Testing:${NC} Create expense without amountEur"
echo "Request: POST ${BASE_URL}/api/expenses"
echo "Response Status: $create_status2"
echo "Response Body: $create_body2"

if [ "$create_status2" -eq 201 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Create expense without amountEur"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Create expense without amountEur (Expected: 201, Got: $create_status2)"
    ((TESTS_FAILED++))
fi
echo "----------------------------------------"

# Extract second expense ID
expense_id2=$(echo "$create_body2" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "Created expense with ID: $expense_id2"

# Extract second expense reference
expense_reference2=$(echo "$create_body2" | grep -o '"expenseReference":"[^"]*"' | cut -d'"' -f4)
echo "Created expense with reference: $expense_reference2"

# Test with very large amount
large_amount='{
  "documentType": "RECEIPT",
  "expenseType": "MEALS",
  "amountOriginal": 9999999.99,
  "currency": "USD",
  "date": "2025-06-30",
  "userId": "user123",
  "expenseStatus": "DRAFT",
  "description": "Very large expense"
}'
test_endpoint "POST" "/api/expenses" 201 "Create expense with very large amount" "$large_amount"

# Test with special characters
special_chars='{
  "documentType": "RECEIPT",
  "expenseType": "MEALS",
  "amountOriginal": 50.00,
  "currency": "USD",
  "date": "2025-06-30",
  "userId": "user123",
  "expenseStatus": "DRAFT",
  "description": "Special chars: !@#$%^&*()_+<>?:{}|~`"
}'
test_endpoint "POST" "/api/expenses" 201 "Create expense with special characters" "$special_chars"

echo
echo "2. Testing Expense Retrieval"
echo "==========================="

# Get the created expense by ID
if [ -n "$expense_id" ]; then
    get_response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/api/expenses/$expense_id")
    get_status=$(echo "$get_response" | tail -n1)
    get_body=$(echo "$get_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Get expense by ID"
    echo "Request: GET ${BASE_URL}/api/expenses/$expense_id"
    echo "Response Status: $get_status"
    echo "Response Body: $get_body"

    if [ "$get_status" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Get expense by ID"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Get expense by ID (Expected: 200, Got: $get_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"
else
    echo "Skipping get expense by ID test - no valid expense ID"
fi

# Test the new search endpoint with various parameters

# Get expenses by status
test_endpoint "GET" "/api/expenses/search?status=DRAFT" 200 "Get expenses by status"

# Get expenses by user ID
test_endpoint "GET" "/api/expenses/search?userId=user123" 200 "Get expenses by user ID"

# Test filtering by both userId AND status
test_endpoint "GET" "/api/expenses/search?userId=user123&status=DRAFT" 200 "Get expenses by userId and status"

# Test search by expense reference
if [ -n "$expense_reference" ]; then
    test_endpoint "GET" "/api/expenses/search?reference=$expense_reference" 200 "Get expense by reference"
else
    echo "Skipping search by reference test - no valid expense reference"
    ((TESTS_FAILED++))
fi

# Test with non-existent user (should return empty list, not 204)
test_endpoint "GET" "/api/expenses/search?userId=nonexistentuser" 200 "Get expenses with no results (empty list)"

echo
echo "3. Testing Expense Updates"
echo "========================="

# Define a standard update payload for reuse
standard_update='{
  "documentType": "RECEIPT",
  "expenseType": "MEALS",
  "amountOriginal": 30.50,
  "amountEur": 25.75,
  "currency": "USD",
  "date": "2025-06-30",
  "userId": "user123",
  "expenseStatus": "SUBMITTED",
  "description": "Updated business lunch",
  "expenseDetails": "Lunch with client and team"
}'

if [ -n "$expense_id" ]; then
    # Update expense details
    update_expense_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/expenses/$expense_id" \
      -H "Content-Type: application/json" \
      -d "$standard_update")
    update_expense_code=$(echo "$update_expense_response" | tail -n1)
    update_expense_body=$(echo "$update_expense_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Update expense details"
    echo "Request: PUT ${BASE_URL}/api/expenses/$expense_id"
    echo "Response Status: $update_expense_code"
    echo "Response Body: $update_expense_body"

    if [ "$update_expense_code" -eq 200 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Update expense details"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Update expense details (Expected: 200, Got: $update_expense_code)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"

    # Test with invalid data
    invalid_update='{
      "documentType": "RECEIPT",
      "expenseType": "MEALS",
      "amountOriginal": -10.00,
      "currency": "USD",
      "date": "2025-06-30",
      "userId": "user123"
    }'
    test_endpoint_expect_fail "PUT" "/api/expenses/$expense_id" 400 "Update expense with invalid data" "$invalid_update"
else
    echo "Skipping update expense tests - no valid expense ID"
    ((TESTS_FAILED+=1))  # Count the skipped test as failure
fi

# Test updating non-existent expense
test_endpoint_expect_fail "PUT" "/api/expenses/non-existent-id" 404 "Update non-existent expense" "$standard_update"

echo
echo "4. Testing Error Handling"
echo "========================"

# Test missing required fields - expecting failure
invalid_expense='{
  "documentType": "RECEIPT",
  "expenseType": "MEALS",
  "currency": "USD",
  "date": "2025-06-30"
}'

test_endpoint_expect_fail "POST" "/api/expenses" 400 "Create expense with missing required fields" "$invalid_expense"

# Test invalid enum value - expecting failure
invalid_enum='{
  "documentType": "INVALID_TYPE",
  "expenseType": "MEALS",
  "amountOriginal": 25.50,
  "currency": "USD",
  "date": "2025-06-30",
  "userId": "user123",
  "expenseStatus": "DRAFT"
}'

test_endpoint_expect_fail "POST" "/api/expenses" 400 "Create expense with invalid enum value" "$invalid_enum"

# Test non-existent expense ID - expecting failure
test_endpoint_expect_fail "GET" "/api/expenses/non-existent-id" 404 "Get non-existent expense"

# Test malformed JSON - using a string that's not valid JSON
malformed_json='{"this is not valid JSON"'
test_endpoint_expect_fail "POST" "/api/expenses" 400 "Create expense with malformed JSON" "$malformed_json"

# Test empty request body
test_endpoint_expect_fail "POST" "/api/expenses" 400 "Create expense with empty body" "{}"

echo
echo "5. Testing Expense Deletion"
echo "=========================="

# Delete the second expense
if [ -n "$expense_id2" ]; then
    delete_response=$(curl -s -w "\n%{http_code}" -X DELETE "${BASE_URL}/api/expenses/$expense_id2")
    delete_status=$(echo "$delete_response" | tail -n1)
    delete_body=$(echo "$delete_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Delete expense"
    echo "Request: DELETE ${BASE_URL}/api/expenses/$expense_id2"
    echo "Response Status: $delete_status"
    echo "Response Body: $delete_body"

    if [ "$delete_status" -eq 204 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Delete expense"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Delete expense (Expected: 204, Got: $delete_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"

    # Verify deletion - expecting failure
    verify_delete_response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/api/expenses/$expense_id2")
    verify_delete_status=$(echo "$verify_delete_response" | tail -n1)
    verify_delete_body=$(echo "$verify_delete_response" | sed '$d')

    echo -e "${YELLOW}Testing:${NC} Verify expense was deleted"
    echo "Request: GET ${BASE_URL}/api/expenses/$expense_id2 (expected to fail)"
    echo "Response Status: $verify_delete_status"
    echo "Response Body: $verify_delete_body"

    if [ "$verify_delete_status" -eq 404 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Verify expense was deleted (failed as expected with HTTP 404)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Verify expense was deleted (should have failed with HTTP 404, but got HTTP $verify_delete_status)"
        ((TESTS_FAILED++))
    fi
    echo "----------------------------------------"

    # Test deleting an already deleted expense (should return 404)
    test_endpoint_expect_fail "DELETE" "/api/expenses/$expense_id2" 404 "Delete already deleted expense"
else
    echo "Skipping delete expense test - no valid expense ID"
    ((TESTS_FAILED+=2))  # Count the skipped tests as failures
fi

# Test deleting non-existent expense
test_endpoint_expect_fail "DELETE" "/api/expenses/non-existent-id" 404 "Delete non-existent expense"

# Print test summary
print_summary "Expenses"
