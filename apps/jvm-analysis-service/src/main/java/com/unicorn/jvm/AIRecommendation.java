package com.unicorn.jvm;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.*;

@Component
public class AIRecommendation {

    private final BedrockRuntimeClient bedrockClient;

    @Value("${aws.bedrock.model_id:global.anthropic.claude-sonnet-4-20250514-v1:0}")
    private String modelId;

    @Value("${aws.bedrock.max_tokens:10000}")
    private int maxTokens;

    public AIRecommendation() {
        this.bedrockClient = BedrockRuntimeClient.builder().build();
    }

    public String analyzePerformance(String threadDump, String profilingData) {
        String systemPrompt = """
            You are an expert in Java performance analysis with extensive experience diagnosing production issues.
            Analyze thread dumps and profiling data to identify performance bottlenecks and provide actionable recommendations.
            Be thorough, specific, and focus on practical solutions.
            """;

        String userPrompt = String.format("""
            Analyze this Java thread dumps and profiling performance data and provide a focused report:

            ## Health Status
            Rate: Healthy/Degraded/Critical with brief explanation

            ## Thread Analysis
            - Total threads: X (X%% RUNNABLE, X%% WAITING, X%% BLOCKED)
            - Key patterns: Describe what threads are doing and why
            - Bottlenecks: Identify specific thread contention or blocking issues

            ## Top Issues (max 3)
            For each critical issue found:
            - **Problem**: Specific technical issue with affected components
            - **Root Cause**: Why this is happening (code/config/resource issue)
            - **Impact**: Quantified performance/stability effect
            - **Fix**: Concrete action with implementation details

            ## Performance Hotspots
            From flamegraph analysis:
            - Top 3 CPU consumers with method names and sample counts
            - Memory allocation patterns and potential leaks
            - I/O bottlenecks (database, network, file operations)
            - Lock contention areas with specific synchronization points

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
            """, threadDump, profilingData);

        Message systemMessage = Message.builder()
                .role(ConversationRole.USER)
                .content(ContentBlock.fromText(systemPrompt))
                .build();

        Message userMessage = Message.builder()
                .role(ConversationRole.USER)
                .content(ContentBlock.fromText(userPrompt))
                .build();

        ConverseRequest request = ConverseRequest.builder()
                .modelId(modelId)
                .messages(systemMessage, userMessage)
                .inferenceConfig(InferenceConfiguration.builder()
                        .maxTokens(maxTokens)
                        .build())
                .build();

        ConverseResponse response = bedrockClient.converse(request);
        return response.output().message().content().getFirst().text();
    }
}