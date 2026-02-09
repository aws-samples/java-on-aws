package com.example.ai.jvmanalyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class AiService {

    private static final Logger logger = LoggerFactory.getLogger(AiService.class);

    private final ChatClient chatClient;
    private final boolean sourceCodeToolsAvailable;

    private static final String SYSTEM_PROMPT = """
        You are a Java performance engineer. You receive two data sources \
        from a production Spring Boot application running on Amazon EKS: \
        a JFR profiling summary (collapsed stacks, CPU load, GC heap, JVM info) \
        and a thread dump snapshot. Both were captured around the time \
        a monitoring alert fired. Analyze the data and report what you find.""";

    public AiService(ChatClient.Builder chatClientBuilder,
                     @Value("${GITHUB_REPO_URL:}") String repoUrl,
                     @Value("${GITHUB_TOKEN:}") String token,
                     @Value("${GITHUB_REPO_PATH:}") String repoPath) {
        var builder = chatClientBuilder.defaultSystem(SYSTEM_PROMPT);

        if (!repoUrl.isBlank()) {
            var tool = new GitHubSourceCodeTool(repoUrl, token, repoPath);
            builder.defaultTools(tool);
            logger.info("Source code tool enabled for: {}/{}", repoUrl, repoPath);
        }

        this.chatClient = builder.build();
        this.sourceCodeToolsAvailable = !repoUrl.isBlank();
    }

    public String analyze(String threadDump, String profilingSummary) {
        var prompt = buildPrompt(threadDump, profilingSummary);

        try {
            logger.info("Sending analysis request to Amazon Bedrock...");
            var response = chatClient.prompt()
                .user(prompt)
                .call()
                .content();
            logger.info("Received analysis response from Amazon Bedrock");
            return response;
        } catch (Exception e) {
            logger.error("AI analysis failed: {}", e.getMessage());
            throw e;
        }
    }

    String buildPrompt(String threadDump, String profilingSummary) {
        var sb = new StringBuilder();
        sb.append("""
            **JFR Profiling Summary:**
            Extracted from an async-profiler wall-clock recording. \
            Contains collapsed stacks with sample counts, CPU load over the \
            sampling window, GC heap state, and JVM configuration.

            %s
            """.formatted(profilingSummary));

        if (threadDump != null) {
            sb.append("""

            **Thread Dump:**
            Snapshot of all JVM threads.

            %s
            """.formatted(threadDump));
        } else {
            sb.append("\n**Thread Dump:** Not available.\n");
        }

        sb.append("""

            ---

            Analyze the available data. Structure your report as:

            ## Health Assessment
            One-line verdict: Healthy / Degraded / Critical.

            ## Findings
            What do you see in the data? Correlate collapsed stacks with thread states \
            where thread dump is available. \
            Flag anything unusual — contention, resource pressure, configuration \
            issues, or patterns that suggest a problem. Cite specific methods, \
            thread names, and numbers.

            ## Recommendations
            Prioritized — most impactful first. Only include actionable items \
            with concrete steps.

            Be concise.
            """);

        if (sourceCodeToolsAvailable) {
            sb.append("""

            ---

            You have access to source code tools. Use them to look up the actual \
            source code of methods that appear in the collapsed stacks and thread dump. \
            In your findings and recommendations, reference specific file paths, \
            class names, and line numbers. Provide concrete code fixes — show the \
            current problematic code and the recommended replacement.
            """);
        }

        return sb.toString();
    }
}
