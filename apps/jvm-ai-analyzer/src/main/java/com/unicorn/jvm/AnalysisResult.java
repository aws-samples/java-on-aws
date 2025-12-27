package com.unicorn.jvm;

// Java 16 Records (JEP 395) - immutable DTOs
public record AnalysisResult(
    String message,
    int count
) {}
