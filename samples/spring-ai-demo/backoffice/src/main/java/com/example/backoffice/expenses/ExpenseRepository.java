package com.example.backoffice.expenses;

import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * Repository for Expense entities providing data access methods.
 */
@Repository
interface ExpenseRepository extends CrudRepository<Expense, String> {
    List<Expense> findByUserId(String userId);
    List<Expense> findByExpenseStatus(Expense.ExpenseStatus expenseStatus);
    List<Expense> findByUserIdAndExpenseStatus(String userId, Expense.ExpenseStatus expenseStatus);
    Optional<Expense> findByExpenseReference(String expenseReference);
}
