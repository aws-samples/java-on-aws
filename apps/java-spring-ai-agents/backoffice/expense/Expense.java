package com.example.backoffice.expense;

import com.example.backoffice.common.BackofficeConstants;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Objects;

@DynamoDbBean
public class Expense {

    public static final String EXPENSE_PREFIX = "EXPENSE#";
    public static final String REFERENCE_PREFIX = "EXP-";

    public enum ExpenseType {
        FLIGHT, HOTEL, MEALS, TRANSPORT, OTHER
    }

    public enum ExpenseStatus {
        DRAFT, SUBMITTED, APPROVED, REJECTED
    }

    private String pk;
    private String sk;
    private String expenseReference;
    private String userId;
    private String tripReference;
    private BigDecimal amount;
    private String currency;
    private LocalDate date;
    private String description;
    private ExpenseType type;
    private ExpenseStatus status;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public Expense() {}

    public static Expense create(String userId, BigDecimal amount, String currency,
                                  LocalDate date, String description, ExpenseType type,
                                  String tripReference) {
        Objects.requireNonNull(userId, "userId is required");
        Objects.requireNonNull(amount, "amount is required");
        Objects.requireNonNull(currency, "currency is required");
        Objects.requireNonNull(date, "date is required");
        Objects.requireNonNull(type, "type is required");

        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("amount must be positive");
        }

        Expense expense = new Expense();
        String id = BackofficeConstants.generateId();
        expense.expenseReference = REFERENCE_PREFIX + id;
        expense.userId = userId;
        expense.pk = BackofficeConstants.USER_PREFIX + userId;
        expense.sk = EXPENSE_PREFIX + expense.expenseReference;
        expense.amount = amount;
        expense.currency = currency.toUpperCase();
        expense.date = date;
        expense.description = description;
        expense.type = type;
        expense.tripReference = (tripReference != null && !tripReference.isBlank()) ? tripReference : null;
        expense.status = ExpenseStatus.DRAFT;
        expense.createdAt = LocalDateTime.now();
        expense.updatedAt = expense.createdAt;
        return expense;
    }

    @DynamoDbPartitionKey
    public String getPk() { return pk; }
    public void setPk(String pk) { this.pk = pk; }

    @DynamoDbSortKey
    public String getSk() { return sk; }
    public void setSk(String sk) { this.sk = sk; }

    @DynamoDbSecondaryPartitionKey(indexNames = "expenseReference-index")
    public String getExpenseReference() { return expenseReference; }
    public void setExpenseReference(String expenseReference) { this.expenseReference = expenseReference; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    @DynamoDbSecondaryPartitionKey(indexNames = "tripReference-index")
    public String getTripReference() { return tripReference; }
    public void setTripReference(String tripReference) { this.tripReference = tripReference; }

    public BigDecimal getAmount() { return amount; }
    public void setAmount(BigDecimal amount) { this.amount = amount; }

    public String getCurrency() { return currency; }
    public void setCurrency(String currency) { this.currency = currency; }

    public LocalDate getDate() { return date; }
    public void setDate(LocalDate date) { this.date = date; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public ExpenseType getType() { return type; }
    public void setType(ExpenseType type) { this.type = type; }

    public ExpenseStatus getStatus() { return status; }
    public void setStatus(ExpenseStatus status) { this.status = status; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Expense expense = (Expense) o;
        return Objects.equals(pk, expense.pk) && Objects.equals(sk, expense.sk);
    }

    @Override
    public int hashCode() {
        return Objects.hash(pk, sk);
    }

    @Override
    public String toString() {
        return "Expense{expenseReference='%s', userId='%s', amount=%s %s, type=%s, status=%s, trip=%s}"
                .formatted(expenseReference, userId, amount, currency, type, status, tripReference);
    }
}
