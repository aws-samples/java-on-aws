package com.unicorn.jvm;

import net.jqwik.api.*;
import net.jqwik.api.constraints.*;

// Property tests for AI analysis prompt building and fallback behavior
class AiAnalysisServiceTest {

    @Property(tries = 100)
    void promptContainsBothInputs(
        @ForAll @StringLength(min = 1, max = 500) String threadDump,
        @ForAll @StringLength(min = 1, max = 500) String profilingData
    ) {
        var service = new TestableAiAnalysisService();
        var prompt = service.buildPrompt(threadDump, profilingData);

        assert prompt.contains(threadDump) : "Prompt should contain thread dump";
        assert prompt.contains(profilingData) : "Prompt should contain profiling data";
    }

    @Property(tries = 100)
    void promptContainsRequiredSections(
        @ForAll @StringLength(min = 10, max = 200) String threadDump,
        @ForAll @StringLength(min = 10, max = 200) String profilingData
    ) {
        var service = new TestableAiAnalysisService();
        var prompt = service.buildPrompt(threadDump, profilingData);

        assert prompt.contains("Health Status") : "Prompt should request Health Status";
        assert prompt.contains("Thread Analysis") : "Prompt should request Thread Analysis";
        assert prompt.contains("Top Issues") : "Prompt should request Top Issues";
        assert prompt.contains("Recommendations") : "Prompt should request Recommendations";
    }

    @Property(tries = 100)
    void fallbackReportContainsErrorInfo(
        @ForAll @StringLength(min = 1, max = 100) String errorMessage,
        @ForAll @StringLength(min = 0, max = 500) String threadDump,
        @ForAll @StringLength(min = 0, max = 500) String profilingData
    ) {
        var exception = new RuntimeException(errorMessage);
        var service = new TestableAiAnalysisService();
        var report = service.buildFallbackReport(exception, threadDump, profilingData);

        assert report != null : "Fallback report should not be null";
        assert report.contains("Error") : "Fallback report should mention error";
        assert report.contains(errorMessage) : "Fallback report should contain error message";
    }

    @Property(tries = 100)
    void fallbackReportContainsInputSizes(
        @ForAll @StringLength(min = 0, max = 1000) String threadDump,
        @ForAll @StringLength(min = 0, max = 1000) String profilingData
    ) {
        var exception = new RuntimeException("Test error");
        var service = new TestableAiAnalysisService();
        var report = service.buildFallbackReport(exception, threadDump, profilingData);

        assert report.contains("Thread dump size") : "Report should mention thread dump size";
        assert report.contains("Profiling data size") : "Report should mention profiling data size";
        assert report.contains(String.valueOf(threadDump.length())) : "Report should contain actual thread dump size";
        assert report.contains(String.valueOf(profilingData.length())) : "Report should contain actual profiling data size";
    }

    @Property(tries = 100)
    void fallbackReportHandlesNullInputs() {
        var exception = new RuntimeException("Test error");
        var service = new TestableAiAnalysisService();
        var report = service.buildFallbackReport(exception, null, null);

        assert report != null : "Fallback report should not be null";
        assert report.contains("0 characters") : "Report should show 0 for null inputs";
    }

    // --- Test helper ---

    private static class TestableAiAnalysisService extends AiAnalysisService {
        TestableAiAnalysisService() {
            super(null);
        }

        @Override
        public String buildPrompt(String threadDump, String profilingData) {
            return super.buildPrompt(threadDump, profilingData);
        }

        @Override
        public String buildFallbackReport(Exception e, String threadDump, String profilingData) {
            return super.buildFallbackReport(e, threadDump, profilingData);
        }
    }
}
