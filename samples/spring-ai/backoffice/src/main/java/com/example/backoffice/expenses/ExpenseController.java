package com.example.backoffice.expenses;

import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.validation.annotation.Validated;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * REST controller for expense-related endpoints.
 * Provides API for CRUD operations on expenses.
 */
@RestController
@RequestMapping("api/expenses")
@Validated
class ExpenseController {
    private final ExpenseService expenseService;
    private static final Logger logger = LoggerFactory.getLogger(ExpenseController.class);

    ExpenseController(ExpenseService expenseService) {
        this.expenseService = expenseService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Expense createExpense(@Valid @RequestBody Expense expense) {
        logger.debug("Creating expense: {}", expense);
        try {
            // Use the object-based service method
            var savedExpense = expenseService.createExpense(expense);
            logger.info("Successfully created expense with ID: {}, reference: {}", 
                savedExpense.getId(), savedExpense.getExpenseReference());
            return savedExpense;
        } catch (Exception e) {
            logger.error("Failed to create expense", e);
            throw e;
        }
    }

    @GetMapping("/search")
    @ResponseStatus(HttpStatus.OK)
    public List<Expense> search(
            @RequestParam(required = false) String userId,
            @RequestParam(required = false) Expense.ExpenseStatus status,
            @RequestParam(required = false) String reference) {

        logger.debug("Searching expenses with userId: {}, status: {}, reference: {}", 
            userId, status, reference);

        try {
            if (reference != null) {
                // If reference is provided, search by reference
                List<Expense> result = new ArrayList<>();
                try {
                    result.add(expenseService.findByExpenseReference(reference));
                } catch (ResponseStatusException e) {
                    // Return empty list if not found
                    logger.info("No expense found with reference: {}", reference);
                }
                return result;
            } else {
                // Otherwise use the consolidated method that handles userId and status
                List<Expense> expenses = expenseService.getExpensesByUserIdAndStatus(userId, status);
                logger.info("Retrieved {} expenses", expenses.size());
                return expenses;
            }
        } catch (ResponseStatusException e) {
            if (e.getStatusCode() == HttpStatus.NOT_FOUND) {
                // Return empty list instead of 404 for search operations
                return Collections.emptyList();
            }
            throw e;
        } catch (Exception e) {
            logger.error("Failed to search expenses: {}", e.getMessage(), e);
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to search expenses: " + e.getMessage(), e);
        }
    }

    @GetMapping("/{expenseId}")
    @ResponseStatus(HttpStatus.OK)
    public Expense getExpense(@PathVariable String expenseId) {
        logger.debug("Retrieving expense with ID: {}", expenseId);
        try {
            var expense = expenseService.getExpense(expenseId);
            logger.info("Successfully retrieved expense with ID: {}", expenseId);
            return expense;
        } catch (Exception e) {
            logger.error("Failed to retrieve expense with ID: {}", expenseId, e);
            throw e;
        }
    }

    @PutMapping("/{expenseId}")
    @ResponseStatus(HttpStatus.OK)
    public Expense updateExpense(
            @PathVariable String expenseId,
            @Valid @RequestBody Expense expense) {

        logger.debug("Updating expense with ID: {}", expenseId);
        try {
            // Use the object-based service method
            var updatedExpense = expenseService.updateExpense(expenseId, expense);
            logger.info("Successfully updated expense with ID: {}", expenseId);
            return updatedExpense;
        } catch (Exception e) {
            logger.error("Failed to update expense with ID: {}", expenseId, e);
            throw e;
        }
    }

    @DeleteMapping("/{expenseId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteExpense(@PathVariable String expenseId) {
        logger.debug("Deleting expense with ID: {}", expenseId);
        try {
            expenseService.deleteExpense(expenseId);
            logger.info("Successfully deleted expense with ID: {}", expenseId);
        } catch (Exception e) {
            logger.error("Failed to delete expense with ID: {}", expenseId, e);
            throw e;
        }
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, List<String>> handleValidationErrors(MethodArgumentNotValidException ex) {
        List<String> errors = ex.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.toList());

        logger.warn("Validation failed: {}", errors);
        return Collections.singletonMap("errors", errors);
    }
}
