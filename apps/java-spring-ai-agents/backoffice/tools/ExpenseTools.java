package com.example.backoffice.expense;

import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Component
public class ExpenseTools {

    private final ExpenseService service;

    public ExpenseTools(ExpenseService service) {
        this.service = service;
    }

    @Bean
    public ToolCallbackProvider expenseToolsProvider(ExpenseTools expenseTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(expenseTools)
                .build();
    }

    @Tool(description = "Create a new expense report. Optionally link to a trip.")
    public Expense createExpense(
            @ToolParam(description = "User ID") String userId,
            @ToolParam(description = "Amount") BigDecimal amount,
            @ToolParam(description = "Currency code (USD, EUR, etc.)") String currency,
            @ToolParam(description = "Expense date (YYYY-MM-DD)") LocalDate date,
            @ToolParam(description = "Description of expense") String description,
            @ToolParam(description = "Type: FLIGHT, HOTEL, MEALS, TRANSPORT, OTHER") Expense.ExpenseType type,
            @ToolParam(description = "Trip reference to link (optional, TRP-XXXXXXXX)") String tripReference) {
        return service.createExpense(userId, amount, currency, date, description, type, tripReference);
    }

    @Tool(description = "Get all expenses for a user")
    public List<Expense> getExpenses(@ToolParam(description = "User ID") String userId) {
        return service.getExpenses(userId);
    }

    @Tool(description = "Get expense details by reference number")
    public Expense getExpense(
            @ToolParam(description = "Expense reference (EXP-XXXXXXXX)") String expenseReference) {
        return service.getExpense(expenseReference);
    }

    @Tool(description = "Get all expenses linked to a specific trip")
    public List<Expense> getExpensesForTrip(
            @ToolParam(description = "Trip reference (TRP-XXXXXXXX)") String tripReference) {
        return service.getExpensesForTrip(tripReference);
    }

    @Tool(description = "Submit a draft expense for approval")
    public Expense submitExpense(
            @ToolParam(description = "Expense reference (EXP-XXXXXXXX)") String expenseReference) {
        return service.submitExpense(expenseReference);
    }
}
