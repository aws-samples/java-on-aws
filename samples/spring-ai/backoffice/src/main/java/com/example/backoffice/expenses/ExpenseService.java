package com.example.backoffice.expenses;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Service for expense-related business operations.
 * Provides methods for CRUD operations and business logic.
 */
@Service
public class ExpenseService {
    private final ExpenseRepository expenseRepository;
    private static final Logger logger = LoggerFactory.getLogger(ExpenseService.class);

    public ExpenseService(ExpenseRepository expenseRepository) {
        this.expenseRepository = expenseRepository;
    }

    /**
     * Creates a new expense from an Expense object.
     * Used by controllers.
     */
    @Transactional
    public Expense createExpense(Expense expense) {
        logger.debug("Creating expense from object: {}", expense);
        validateExpense(expense);
        var savedExpense = expenseRepository.save(expense);
        logger.debug("Created expense with ID: {}, reference: {}",
                savedExpense.getId(), savedExpense.getExpenseReference());
        return savedExpense;
    }

    /**
     * Creates a new expense with the provided details.
     * Used by tools layer.
     */
    @Transactional
    public Expense createExpense(
            Expense.DocumentType documentType,
            Expense.ExpenseType expenseType,
            BigDecimal amountOriginal,
            BigDecimal amountEur,
            String currency,
            LocalDate date,
            String userId,
            String description,
            String expenseDetails,
            Expense.ExpenseStatus expenseStatus) {

        logger.debug("Creating expense for user: {}, amount: {} {}, type: {}",
                userId, amountOriginal, currency, expenseType);

        Expense expense = new Expense();
        expense.setDocumentType(documentType);
        expense.setExpenseType(expenseType);
        expense.setAmountOriginal(amountOriginal);
        expense.setAmountEur(amountEur);
        expense.setCurrency(currency);
        expense.setDate(date);
        expense.setUserId(userId);
        expense.setDescription(description);
        expense.setExpenseDetails(expenseDetails);
        expense.setExpenseStatus(expenseStatus != null ? expenseStatus : Expense.ExpenseStatus.DRAFT);

        return createExpense(expense);
    }

    /**
     * Retrieves expenses based on userId and/or status.
     * Returns empty list if no expenses are found.
     */
    @Transactional(readOnly = true)
    public List<Expense> getExpensesByUserIdAndStatus(String userId, Expense.ExpenseStatus status) {
        if (userId != null && status != null) {
            logger.debug("Retrieving expenses for user ID: {} with status: {}", userId, status);
            try {
                if (userId.trim().isEmpty()) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "User ID cannot be empty");
                }
                return expenseRepository.findByUserIdAndExpenseStatus(userId, status);
            } catch (ResponseStatusException e) {
                throw e;
            } catch (Exception e) {
                logger.error("Error retrieving expenses for user ID {} with status {}: {}",
                        userId, status, e.getMessage(), e);
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                        "Error retrieving expenses by user ID and status: " + e.getMessage(), e);
            }
        } else if (userId != null) {
            logger.debug("Retrieving expenses for user ID: {}", userId);
            try {
                if (userId.trim().isEmpty()) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "User ID cannot be empty");
                }
                return expenseRepository.findByUserId(userId);
            } catch (ResponseStatusException e) {
                throw e;
            } catch (Exception e) {
                logger.error("Error retrieving expenses for user ID {}: {}", userId, e.getMessage(), e);
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                        "Error retrieving expenses for user ID: " + e.getMessage(), e);
            }
        } else if (status != null) {
            logger.debug("Retrieving expenses with status: {}", status);
            try {
                return expenseRepository.findByExpenseStatus(status);
            } catch (ResponseStatusException e) {
                throw e;
            } catch (Exception e) {
                logger.error("Error retrieving expenses with status {}: {}", status, e.getMessage(), e);
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                        "Error retrieving expenses by status: " + e.getMessage(), e);
            }
        } else {
            // If both userId and status are null, return all expenses
            logger.debug("Retrieving all expenses");
            try {
                List<Expense> expenses = new ArrayList<>();
                expenseRepository.findAll().forEach(expenses::add);
                logger.debug("Retrieved {} expenses", expenses.size());
                return expenses;
            } catch (Exception e) {
                logger.error("Error retrieving all expenses: {}", e.getMessage(), e);
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                        "Error retrieving all expenses: " + e.getMessage(), e);
            }
        }
    }

    /**
     * Updates an existing expense from an Expense object.
     * Used by controllers.
     */
    @Transactional
    public Expense updateExpense(String expenseId, Expense expense) {
        logger.debug("Updating expense with ID: {} from object", expenseId);

        // Verify existence
        getExpense(expenseId);

        // Set the ID to ensure we're updating the right record
        expense.setId(expenseId);
        validateExpense(expense);

        var savedExpense = expenseRepository.save(expense);
        logger.debug("Updated expense with ID: {}", expenseId);
        return savedExpense;
    }

    /**
     * Updates an existing expense with the provided details.
     * Used by tools layer.
     */
    @Transactional
    public Expense updateExpense(
            String expenseId,
            Expense.DocumentType documentType,
            Expense.ExpenseType expenseType,
            BigDecimal amountOriginal,
            BigDecimal amountEur,
            String currency,
            LocalDate date,
            String userId,
            String description,
            String expenseDetails,
            Expense.ExpenseStatus expenseStatus) {

        logger.debug("Updating expense with ID: {} using parameters", expenseId);

        // Verify existence
        Expense existingExpense = getExpense(expenseId);

        // Update fields
        existingExpense.setDocumentType(documentType);
        existingExpense.setExpenseType(expenseType);
        existingExpense.setAmountOriginal(amountOriginal);
        existingExpense.setAmountEur(amountEur);
        existingExpense.setCurrency(currency);
        existingExpense.setDate(date);
        existingExpense.setUserId(userId);
        existingExpense.setDescription(description);
        existingExpense.setExpenseDetails(expenseDetails);
        existingExpense.setExpenseStatus(expenseStatus);
        existingExpense.setUpdatedAt(LocalDateTime.now());

        return updateExpense(expenseId, existingExpense);
    }

    /**
     * Retrieves an expense by its technical ID.
     * Throws NOT_FOUND if expense doesn't exist.
     */
    @Transactional(readOnly = true)
    public Expense getExpense(String expenseId) {
        logger.debug("Retrieving expense with ID: {}", expenseId);
        return expenseRepository.findById(expenseId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        String.format("Expense not found with ID: %s", expenseId)));
    }

    /**
     * Retrieves an expense by its business identifier (expenseReference).
     * Throws NOT_FOUND if expense doesn't exist.
     */
    @Transactional(readOnly = true)
    public Expense findByExpenseReference(String expenseReference) {
        logger.debug("Retrieving expense with reference: {}", expenseReference);
        return expenseRepository.findByExpenseReference(expenseReference)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        String.format("Expense not found with reference: %s", expenseReference)));
    }

    /**
     * Deletes an expense by its ID.
     * Throws NOT_FOUND if expense doesn't exist.
     */
    @Transactional
    public void deleteExpense(String expenseId) {
        logger.debug("Deleting expense with ID: {}", expenseId);
        var expense = getExpense(expenseId);
        expenseRepository.delete(expense);
        logger.debug("Deleted expense with ID: {}", expenseId);
    }

    private void validateExpense(Expense expense) {
        if (expense == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Expense cannot be null");
        }
        if (expense.getAmountOriginal() == null || expense.getAmountOriginal().compareTo(java.math.BigDecimal.ZERO) <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Original expense amount must be greater than zero");
        }
        if (expense.getCurrency() == null || expense.getCurrency().trim().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Currency is required");
        }
        if (expense.getUserId() == null || expense.getUserId().trim().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "User ID is required");
        }
        if (expense.getExpenseType() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Expense type is required");
        }
        if (expense.getDocumentType() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Document type is required");
        }
    }
}
