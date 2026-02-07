package com.example.backoffice.expense;

import com.example.backoffice.common.BackofficeConstants;
import com.example.backoffice.exception.InvalidOperationException;
import com.example.backoffice.exception.ResourceNotFoundException;
import com.example.backoffice.trip.TripService;
import io.awspring.cloud.dynamodb.DynamoDbTemplate;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.model.QueryConditional;
import software.amazon.awssdk.enhanced.dynamodb.model.QueryEnhancedRequest;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
public class ExpenseService {

    private final DynamoDbTemplate dynamoDbTemplate;
    private final TripService tripService;

    public ExpenseService(DynamoDbTemplate dynamoDbTemplate, TripService tripService) {
        this.dynamoDbTemplate = dynamoDbTemplate;
        this.tripService = tripService;
    }

    public Expense createExpense(String userId, BigDecimal amount, String currency,
                                  LocalDate date, String description, Expense.ExpenseType type,
                                  String tripReference) {
        if (tripReference != null && !tripReference.isBlank()) {
            tripService.getTrip(tripReference);
        }
        Expense expense = Expense.create(userId, amount, currency, date, description, type, tripReference);
        return dynamoDbTemplate.save(expense);
    }

    public List<Expense> getExpenses(String userId) {
        QueryEnhancedRequest request = QueryEnhancedRequest.builder()
                .queryConditional(QueryConditional.sortBeginsWith(
                        Key.builder()
                                .partitionValue(BackofficeConstants.USER_PREFIX + userId)
                                .sortValue(Expense.EXPENSE_PREFIX)
                                .build()))
                .build();
        return dynamoDbTemplate.query(request, Expense.class).items().stream().toList();
    }

    public List<Expense> getExpensesForTrip(String tripReference) {
        tripService.getTrip(tripReference);

        QueryEnhancedRequest request = QueryEnhancedRequest.builder()
                .queryConditional(QueryConditional.keyEqualTo(
                        Key.builder().partitionValue(tripReference).build()))
                .build();
        return dynamoDbTemplate.query(request, Expense.class, "tripReference-index")
                .items().stream().toList();
    }

    public Expense submitExpense(String expenseReference) {
        Expense expense = getExpense(expenseReference);
        if (expense.getStatus() != Expense.ExpenseStatus.DRAFT) {
            throw new InvalidOperationException("Only draft expenses can be submitted");
        }
        expense.setStatus(Expense.ExpenseStatus.SUBMITTED);
        expense.setUpdatedAt(LocalDateTime.now());
        return dynamoDbTemplate.save(expense);
    }

    public Expense getExpense(String expenseReference) {
        QueryEnhancedRequest request = QueryEnhancedRequest.builder()
                .queryConditional(QueryConditional.keyEqualTo(
                        Key.builder().partitionValue(expenseReference).build()))
                .build();
        return dynamoDbTemplate.query(request, Expense.class, "expenseReference-index")
                .items().stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Expense", expenseReference));
    }
}
