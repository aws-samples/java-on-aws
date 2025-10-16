package com.example.backoffice.expenses;

import com.example.backoffice.common.ReferenceGenerator;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Column;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Enumerated;
import jakarta.persistence.EnumType;
import jakarta.persistence.Table;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Entity representing an expense record in the system.
 * Contains both technical ID and business identifier (expenseReference).
 */
@Entity
@Table(name = "expenses")
class Expense {

    enum DocumentType {
        RECEIPT, INVOICE, TICKET, BILL, OTHER
    }

    enum ExpenseType {
        MEALS, TRANSPORTATION, OFFICE_SUPPLIES, ACCOMMODATION, HOTEL, OTHER
    }

    enum ExpenseStatus {
        DRAFT, SUBMITTED, PROCESSING, APPROVED, REJECTED
    }

    enum PolicyStatus {
        APPROVED, REQUIRES_MANAGER_APPROVAL, REQUIRES_DIRECTOR_APPROVAL, REQUIRES_EXECUTIVE_APPROVAL, POLICY_VIOLATION
    }

    @Id
    @Column(name = "id")
    private String id;

    @Column(name = "expense_reference", unique = true)
    @Size(max = 10, message = "Expense reference must not exceed 10 characters")
    private String expenseReference;

    @Column(name = "document_type")
    @NotNull(message = "Document type is required")
    @Enumerated(EnumType.STRING)
    private DocumentType documentType;

    @Column(name = "expense_type")
    @NotNull(message = "Expense type is required")
    @Enumerated(EnumType.STRING)
    private ExpenseType expenseType;

    @Column(name = "amount_original")
    @NotNull(message = "Original amount is required")
    @DecimalMin(value = "0.01", message = "Original amount must be greater than zero")
    private BigDecimal amountOriginal;

    // Calculated field - no validation constraints
    @Column(name = "amount_eur")
    private BigDecimal amountEur;

    @NotBlank(message = "Currency is required")
    private String currency;

    @NotNull(message = "Date is required")
    private LocalDate date;

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @Column(name = "user_id")
    private String userId;

    @Column(name = "expense_status")
    @Enumerated(EnumType.STRING)
    private ExpenseStatus expenseStatus;

    // Policy compliance
    @Column(name = "policy_status")
    @Enumerated(EnumType.STRING)
    private PolicyStatus policyStatus;

    @Column(name = "approval_reason")
    private String approvalReason;

    @Column(name = "policy_notes")
    private String policyNotes;

    // Category-specific fields
    @Column(name = "expense_details", columnDefinition = "TEXT")
    private String expenseDetails;

    private String description;

    Expense() {
    }

    @PrePersist
    protected void onCreate() {
        if (id == null || id.trim().isEmpty()) {
            id = UUID.randomUUID().toString();
        }

        if (expenseReference == null || expenseReference.trim().isEmpty()) {
            expenseReference = ReferenceGenerator.generateWithPrefix("EXP", 6);
        }

        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();

        if (expenseStatus == null) {
            expenseStatus = ExpenseStatus.DRAFT;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    // Getters and Setters
    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getExpenseReference() {
        return expenseReference;
    }

    public void setExpenseReference(String expenseReference) {
        this.expenseReference = expenseReference;
    }

    public DocumentType getDocumentType() {
        return documentType;
    }

    public void setDocumentType(DocumentType documentType) {
        this.documentType = documentType;
    }

    public ExpenseType getExpenseType() {
        return expenseType;
    }

    public void setExpenseType(ExpenseType expenseType) {
        this.expenseType = expenseType;
    }

    public BigDecimal getAmountOriginal() {
        return amountOriginal;
    }

    public void setAmountOriginal(BigDecimal amountOriginal) {
        this.amountOriginal = amountOriginal;
    }

    public BigDecimal getAmountEur() {
        return amountEur;
    }

    public void setAmountEur(BigDecimal amountEur) {
        this.amountEur = amountEur;
    }

    public String getCurrency() {
        return currency;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public ExpenseStatus getExpenseStatus() {
        return expenseStatus;
    }

    public void setExpenseStatus(ExpenseStatus expenseStatus) {
        this.expenseStatus = expenseStatus;
    }

    public PolicyStatus getPolicyStatus() {
        return policyStatus;
    }

    public void setPolicyStatus(PolicyStatus policyStatus) {
        this.policyStatus = policyStatus;
    }

    public String getApprovalReason() {
        return approvalReason;
    }

    public void setApprovalReason(String approvalReason) {
        this.approvalReason = approvalReason;
    }

    public String getPolicyNotes() {
        return policyNotes;
    }

    public void setPolicyNotes(String policyNotes) {
        this.policyNotes = policyNotes;
    }

    public String getExpenseDetails() {
        return expenseDetails;
    }

    public void setExpenseDetails(String expenseDetails) {
        this.expenseDetails = expenseDetails;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
