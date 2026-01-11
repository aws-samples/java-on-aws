package com.example.ai.jvmanalyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@Service
public class AiService {

    private static final Logger logger = LoggerFactory.getLogger(AiService.class);

    private final ChatClient chatClient;

    private static final String SYSTEM_PROMPT = """
        You are an expert in Java performance analysis with extensive experience \
        diagnosing production issues. Analyze thread dumps and profiling data to \
        identify performance bottlenecks and provide actionable recommendations. \
        Be thorough, specific, and focus on practical solutions.""";

    public AiService(ChatClient.Builder chatClientBuilder) {
        if (chatClientBuilder != null) {
            this.chatClient = chatClientBuilder
                .defaultSystem(SYSTEM_PROMPT)
                .build();
        } else {
            this.chatClient = null;
        }
    }

    public String analyze(String threadDump, String profilingData) {
        var prompt = buildPrompt(threadDump, profilingData);

        try {
            logger.info("Sending analysis request to Bedrock...");
            var response = chatClient.prompt()
                .user(prompt)
                .call()
                .content();
            logger.info("Received analysis response from Bedrock");
            return response;
        } catch (Exception e) {
            logger.warn("AI analysis failed: {}", e.getMessage());
            return buildFallbackReport(e, threadDump, profilingData);
        }
    }

    String buildPrompt(String threadDump, String profilingData) {
        return """
            Analyze this Java performance data and provide a focused report:

            ## Health Status
            Rate: Healthy/Degraded/Critical with brief explanation

            ## Thread Analysis
            - Total threads and state distribution (RUNNABLE, WAITING, BLOCKED)
            - Key patterns: what threads are doing and why
            - Bottlenecks: specific thread contention or blocking issues

            ## Top Issues (max 3)
            For each critical issue found:
            - **Problem**: Specific technical issue with affected components
            - **Root Cause**: Why this is happening (code/config/resource issue)
            - **Impact**: Quantified performance/stability effect
            - **Fix**: Concrete action with implementation details

            ## Performance Hotspots
            From flamegraph analysis:
            - Top 3 CPU consumers with method names
            - Memory allocation patterns
            - I/O bottlenecks (database, network, file operations)
            - Lock contention areas

            ## Recommendations
            **Immediate (< 1 day)**:
            - 3 quick configuration or code changes

            **Short-term (< 1 week)**:
            - 3 architectural improvements with expected impact

            **Thread Dump:**
            %s

            **Flamegraph Data:**
            %s

            Provide specific method names, class names, and quantified metrics where possible.
            Keep response under 5KB but include enough detail for actionable insights.
            """.formatted(threadDump, profilingData);
    }

    String buildFallbackReport(Exception e, String threadDump, String profilingData) {
        return """
            # Thread Dump Analysis Report

            **Generated:** %s

            **Error:** AI analysis failed - %s

            ## Inputs Summary
            - Thread dump size: %d characters
            - Profiling data size: %d characters

            ## Manual Review Required
            The AI analysis could not be completed. Please review the thread dump \
            and profiling data manually or retry the analysis.

            ## Thread Dump Preview
            ```
            %s
            ```
            """.formatted(
                LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME),
                e.getMessage(),
                threadDump != null ? threadDump.length() : 0,
                profilingData != null ? profilingData.length() : 0,
                threadDump != null ? threadDump.substring(0, Math.min(500, threadDump.length())) : "N/A"
            );
    }
}
