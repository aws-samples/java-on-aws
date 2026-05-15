package com.example.perf.analyzer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;

/**
 * Spring AI + Amazon Bedrock Converse. Builds one {@link ChatClient}
 * configured with the system prompt and the two tools the model calls:
 * {@link PyroscopeTool} and {@link GitHubSourceCodeTool}.
 *
 * Both tools are singletons. Per-analysis context (workload service name,
 * time window, repo coordinates) is communicated to the model through the
 * user prompt — the model passes those values back when it calls a tool.
 */
@Service
public class AiService {

    private static final Logger logger = LoggerFactory.getLogger(AiService.class);

    private static final String SYSTEM_PROMPT = """
        You are a Java performance engineer. You receive:
          - pre-aggregated Pyroscope top-functions tables for the target
            service in two views: CPU profile (process_cpu) and wall-clock
            profile (wall). CPU shows what is actually computing on a core;
            wall shows where every sampled thread spends time, regardless of
            state. CPU is the right lens for finding new computation; wall
            is the right lens for finding contention, blocked I/O, and
            downstream waits.
          - a JFR summary covering GC pauses, JIT compilation, deoptimization,
            monitor contention, safepoints and JVM configuration.
          - a thread dump.
        All were captured around the time an alert fired or a developer
        triggered an on-demand analysis.

        Cross-check across signals: a method that appears hot in the wall
        profile and shows blocked or waiting threads in the dump is the
        same observation in two lenses. A method that appears hot in CPU
        but quiet in wall is real on-CPU work, not waiting. Pay particular
        attention to *application* (project package) frames — they identify
        the caller in the user's code and are usually the right anchor for
        a finding even when the actual time is burned in a low-level frame
        underneath (HashMap, futex, JIT helper, glibc lock primitive); the
        low-level frame is the mechanism, the application frame is the
        cause. Analyze the data and report what you find.
        """;

    private final ChatClient chatClient;

    public AiService(
        ChatClient.Builder chatClientBuilder,
        PyroscopeTool pyroscopeTool,
        GitHubSourceCodeTool githubSourceCodeTool
    ) {
        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            .defaultTools(pyroscopeTool, githubSourceCodeTool)
            .build();
    }

    /** Runs the analysis and returns the Markdown report content. */
    public String analyze(AnalysisService.AnalysisContext ctx) {
        var hasRepo = ctx.githubRepo() != null && !ctx.githubRepo().isBlank();
        var prompt = buildPrompt(ctx, hasRepo);

        logger.info("Sending analysis request to Amazon Bedrock: analysisId={} service={} repo={}",
            ctx.analysisId(), ctx.request().service(), hasRepo ? ctx.githubRepo() : "(none)");

        var response = chatClient.prompt().user(prompt).call().content();

        logger.info("Received analysis response from Amazon Bedrock: analysisId={} length={}",
            ctx.analysisId(), response == null ? 0 : response.length());
        return response == null ? "# Analysis\n\n_Model returned no content._\n" : response;
    }

    String buildPrompt(AnalysisService.AnalysisContext ctx, boolean sourceCodeAvailable) {
        var r = ctx.request();
        var sb = new StringBuilder();

        sb.append("## Context\n\n");
        sb.append("- service: **").append(r.service()).append("**\n");
        sb.append("- platform: **").append(r.platform().name().toLowerCase().replace('_', '-')).append("**\n");
        sb.append("- target: **").append(r.target()).append("**\n");
        sb.append("- trigger: ").append(r.source()).append("\n");
        if (r.reason() != null && !r.reason().isBlank()) {
            sb.append("- reason: ").append(r.reason()).append("\n");
        }
        sb.append("- analysisId: ").append(ctx.analysisId()).append("\n\n");

        // Top-functions snapshots in both lenses. Same window, two lenses on
        // the same workload state.
        sb.append("## Pyroscope top functions (pre-fetched)\n\n")
            .append("Two lenses on the same window. Use **CPU** to find what is computing right now; ")
            .append("use **wall** to find what is waiting on locks, I/O, or downstream calls right now.\n\n");

        sb.append("### CPU (process_cpu)\n\n")
            .append(ctx.pyroscopeCpuTopFunctionsMarkdown() == null
                ? "_Pyroscope CPU data unavailable._\n"
                : ctx.pyroscopeCpuTopFunctionsMarkdown())
            .append("\n\n");

        sb.append("### Wall (wall)\n\n")
            .append(ctx.pyroscopeWallTopFunctionsMarkdown() == null
                ? "_Pyroscope wall data unavailable._\n"
                : ctx.pyroscopeWallTopFunctionsMarkdown())
            .append("\n\n");

        sb.append("## JFR summary\n\n")
            .append(ctx.jfrSummaryMarkdown() == null
                ? "_JFR summary unavailable._\n"
                : ctx.jfrSummaryMarkdown())
            .append("\n\n");

        sb.append("## Thread dump (head)\n\n```\n")
            .append(ctx.threadDumpText() == null ? "(unavailable)" : truncateLines(ctx.threadDumpText(), 200))
            .append("\n```\n\n");

        sb.append("""
            ---

            Analyze the available data. Structure your report as:

            ## Health Assessment
            One-line verdict: Healthy / Degraded / Critical.

            ## Findings
            Correlate the Pyroscope ranked functions (CPU and wall) with JFR
            events and thread states. Distinguish on-CPU work (CPU view) from
            blocking waits and contention (wall view). Flag resource pressure,
            configuration issues, or patterns that suggest a problem. Cite
            specific methods, thread names, and numbers.

            ## Recommendations
            Prioritized — most impactful first. Only include actionable items
            with concrete steps.

            Be concise.
            """);

        sb.append("""

            ---

            You have a Pyroscope query tool you can invoke to request
            additional time windows or narrower label selectors if you need
            to confirm a hypothesis before writing the report.
            """);

        if (sourceCodeAvailable) {
            sb.append("""

                You also have a GitHub source-code tool. Use it to look up
                the actual source of methods that appear in Pyroscope top
                functions, JFR events, or the thread dump. The target
                workload's source lives at:

                """);
            sb.append("- repo: `").append(ctx.githubRepo()).append("`\n");
            var path = ctx.githubPath() == null ? "" : ctx.githubPath();
            sb.append("- pathPrefix: `").append(path).append("`\n\n");
            sb.append("""
                Pass those values along with the file path on every call.
                In your findings and recommendations, reference specific
                file paths, class names and line numbers. Provide concrete
                code fixes — show the current problematic code and the
                recommended replacement.
                """);
        }

        return sb.toString();
    }

    private static String truncateLines(String text, int maxLines) {
        var lines = text.split("\\R", -1);
        if (lines.length <= maxLines) return text;
        var sb = new StringBuilder();
        for (int i = 0; i < maxLines; i++) sb.append(lines[i]).append('\n');
        sb.append("... (truncated, ").append(lines.length - maxLines).append(" more lines)");
        return sb.toString();
    }
}
