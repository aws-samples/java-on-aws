package com.example.backoffice.expenses;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * Tools class for AI-assisted expense operations.
 * Separates tool-annotated methods from the service layer.
 */
@Component
public class ExpenseTools {
    private final ExpenseService expenseService;
    private static final Logger logger = LoggerFactory.getLogger(ExpenseTools.class);

    public ExpenseTools(ExpenseService expenseService) {
        this.expenseService = expenseService;
    }

    @Bean
    public ToolCallbackProvider expenseToolsProvider(ExpenseTools expenseTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(expenseTools)
                .build();
    }

    @Tool(description = """
        Create a new expense, register new expense report.
        Requires: documentType - Type of document (RECEIPT, INVOICE, TICKET, BILL, OTHER),
                 expenseType - Type of expense (MEALS, TRANSPORTATION, OFFICE_SUPPLIES, ACCOMMODATION, HOTEL, OTHER),
                 amountOriginal - Original amount of the expense,
                 currency - Currency code (USD, EUR, etc.),
                 date - Date of the expense (YYYY-MM-DD),
                 userId - ID of the user who created the expense,
                 description - Brief description of the expense.
                 amountEur - Amount in EUR if different from original currency,
                 expenseStatus - Status of the expense (default: DRAFT. DRAFT, SUBMITTED, PROCESSING, APPROVED, REJECTED),
                 expenseDetails - Detailed description of the expense,
                 policyNotes - notes from travel and expenses policy
                 policyStatus - Status of assessment according to travel and expenses policy (APPROVED, REQUIRES_MANAGER_APPROVAL, REQUIRES_DIRECTOR_APPROVAL, REQUIRES_EXECUTIVE_APPROVAL, POLICY_VIOLATION)
                 approvalReason - reason of approval
        Returns: The created expense with generated ID and timestamps.
        Errors: BAD_REQUEST if required fields are missing or invalid.
        """)
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

        logger.debug("Tool: Creating expense for user: {}, amount: {} {}, type: {}",
                userId, amountOriginal, currency, expenseType);

        return expenseService.createExpense(
                documentType,
                expenseType,
                amountOriginal,
                amountEur,
                currency,
                date,
                userId,
                description,
                expenseDetails,
                expenseStatus);
    }

    @Tool(description = """
        Retrieve a specific expense by its unique ID.
        Requires: expenseId - The unique identifier of the expense.
        Returns: The expense details if found.
        Errors: NOT_FOUND if expense doesn't exist.
        """)
    public Expense getExpense(String expenseId) {
        logger.debug("Tool: Retrieving expense with ID: {}", expenseId);
        return expenseService.getExpense(expenseId);
    }

    @Tool(description = """
        Search for expenses by user ID and/or status.
        Parameters: userId - Optional ID of the user who created the expenses,
                   status - Optional status of the expenses (DRAFT, SUBMITTED, etc.).
        Returns: List of expenses matching the criteria.
        """)
    public List<Expense> searchExpenses(String userId, Expense.ExpenseStatus status) {
        logger.debug("Tool: Searching expenses with userId: {} and status: {}", userId, status);
        return expenseService.getExpensesByUserIdAndStatus(userId, status);
    }

    @Tool(description = """
        Update an existing expense.
        Requires: expenseId - The unique identifier of the expense to update,
                 documentType - Type of document (RECEIPT, INVOICE, etc.),
                 expenseType - Type of expense (MEALS, TRANSPORTATION, etc.),
                 amountOriginal - Original amount of the expense,
                 currency - Currency code (USD, EUR, etc.),
                 date - Date of the expense (YYYY-MM-DD),
                 userId - ID of the user who created the expense,
                 description - Brief description of the expense.
                 amountEur - Amount in EUR if different from original currency,
                 expenseStatus - Status of the expense,
                 expenseDetails - Detailed description of the expense.
        Returns: The updated expense.
        Errors: NOT_FOUND if expense doesn't exist, BAD_REQUEST if fields are invalid.
        """)
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

        logger.debug("Tool: Updating expense with ID: {}", expenseId);
        return expenseService.updateExpense(
                expenseId,
                documentType,
                expenseType,
                amountOriginal,
                amountEur,
                currency,
                date,
                userId,
                description,
                expenseDetails,
                expenseStatus);
    }

    @Tool(description = """
        Delete an expense by its unique ID.
        Requires: expenseId - The unique identifier of the expense to delete.
        Returns: Nothing.
        Errors: NOT_FOUND if expense doesn't exist.
        """)
    public void deleteExpense(String expenseId) {
        logger.debug("Tool: Deleting expense with ID: {}", expenseId);
        expenseService.deleteExpense(expenseId);
    }
}
