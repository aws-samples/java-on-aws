package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.Base64;

/**
 * Spring AI + Amazon Bedrock Converse. Builds one {@link ChatClient}
 * configured with the system prompt and the always-registered
 * {@link PyroscopeTool}, then per-analysis layers in a
 * {@link GitHubSourceCodeTool} if the target workload advertised a
 * GitHub repo via pod annotation or task tag.
 *
 * Per-analysis tool registration lets the analyzer serve many workloads
 * whose sources live in different repositories without any environment
 * configuration on the analyzer side.
 */
@Service
public class AiService {

    private static final Logger logger = LoggerFactory.getLogger(AiService.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final String SYSTEM_PROMPT = """
        You are a Java performance engineer. You receive a pre-aggregated
        Pyroscope top functions table, a JFR summary covering GC pauses,
        JIT compilation, deoptimization, monitor contention, safepoints
        and JVM configuration, and a thread dump. All were captured around
        the time an alert fired or a developer triggered an on-demand
        analysis. Analyze the data and report what you find.
        """;

    private final ChatClient chatClient;
    private final PyroscopeTool pyroscopeTool;
    private final String githubToken;

    public AiService(
        ChatClient.Builder chatClientBuilder,
        PyroscopeTool pyroscopeTool,
        @Value("${GITHUB_TOKEN:}") String githubToken
    ) {
        this.pyroscopeTool = pyroscopeTool;
        this.githubToken = githubToken;
        this.chatClient = chatClientBuilder
            .defaultSystem(SYSTEM_PROMPT)
            .defaultTools(pyroscopeTool)
            .build();
    }

    /** Runs the analysis and returns the Markdown report content. */
    public String analyze(AnalysisService.AnalysisContext ctx) {
        var sourceCodeTool = buildSourceCodeTool(ctx);
        var prompt = buildPrompt(ctx, sourceCodeTool != null);

        logger.info("Sending analysis request to Amazon Bedrock: analysisId={} service={} sourceTool={}",
            ctx.analysisId(), ctx.request().service(), sourceCodeTool != null);

        var spec = chatClient.prompt().user(prompt);
        if (sourceCodeTool != null) {
            spec = spec.tools(sourceCodeTool);
        }
        var response = spec.call().content();

        logger.info("Received analysis response from Amazon Bedrock: analysisId={} length={}",
            ctx.analysisId(), response == null ? 0 : response.length());
        return response == null ? "# Analysis\n\n_Model returned no content._\n" : response;
    }

    private GitHubSourceCodeTool buildSourceCodeTool(AnalysisService.AnalysisContext ctx) {
        if (ctx.githubRepo() == null || ctx.githubRepo().isBlank()) return null;
        return new GitHubSourceCodeTool(ctx.githubRepo(), ctx.githubPath(), githubToken);
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

        sb.append("## Pyroscope top functions (pre-fetched)\n\n")
            .append(ctx.pyroscopeTopFunctionsMarkdown() == null
                ? "_Pyroscope data unavailable._\n"
                : ctx.pyroscopeTopFunctionsMarkdown())
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
            Correlate the Pyroscope ranked functions with JFR events and
            thread states. Flag contention, resource pressure, configuration
            issues, or patterns that suggest a problem. Cite specific methods,
            thread names, and numbers.

            ## Recommendations
            Prioritized — most impactful first. Only include actionable items
            with concrete steps.

            Be concise.
            """);

        if (sourceCodeAvailable) {
            sb.append("""

                ---

                You have a source code tool. Use it to look up the actual
                source of methods that appear in Pyroscope top functions,
                JFR events, or the thread dump. In your findings and
                recommendations, reference specific file paths, class names
                and line numbers. Provide concrete code fixes — show the
                current problematic code and the recommended replacement.
                """);
        }

        sb.append("""

            You also have a Pyroscope query tool you can invoke to request
            additional time windows or narrower label selectors if you need
            to confirm a hypothesis before writing the report.
            """);

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

    /**
     * Spring AI @Tool: fetch source code from a GitHub repository via the
     * REST API. The repo coordinates are per-analysis — the target
     * workload advertises them via the pod annotation
     * {@code perf-profile/github-repo} (or the ECS task tag
     * {@code perf-profile:github-repo}). The analyzer constructs a fresh
     * instance each request.
     *
     * Compare {@link PyroscopeTool}, which is a top-level @Component
     * because {@link AnalysisService} also invokes it directly for the
     * pre-fetched prompt section.
     */
    static class GitHubSourceCodeTool {

        private final RestClient restClient;
        private final String repoPath;

        /**
         * @param repo   "{owner}/{name}" (e.g. "aws-samples/java-on-aws")
         * @param path   optional path-prefix inside the repo (e.g. "apps/unicorn-store-spring")
         * @param token  optional GitHub PAT for private repos
         */
        GitHubSourceCodeTool(String repo, String path, String token) {
            if (repo == null || repo.isBlank()) {
                throw new IllegalArgumentException("repo must not be blank");
            }
            var builder = RestClient.builder()
                .baseUrl("https://api.github.com/repos/" + repo.replaceAll("/$", ""))
                .defaultHeader("Accept", "application/vnd.github.v3+json")
                .defaultHeader("User-Agent", "perf-analyzer");
            if (token != null && !token.isBlank()) {
                builder.defaultHeader("Authorization", "token " + token);
            }
            this.restClient = builder.build();
            this.repoPath = (path != null && !path.isBlank())
                ? path.replaceAll("/$", "") : "";
        }

        @Tool(description = """
            Fetch a source code file from the application GitHub repository.
            Provide the path relative to the application root, e.g.
            src/main/java/com/unicorn/store/service/UnicornService.java — the
            repository base path is prepended automatically.
            Use this to look up Java source files referenced in stack traces,
            thread dumps, and JFR event summaries so recommendations can cite
            file paths and line numbers.
            """)
        public String fetchSourceCode(String filePath) {
            var fullPath = repoPath.isEmpty() ? filePath : repoPath + "/" + filePath;
            try {
                var json = restClient.get()
                    .uri("/contents/{path}", fullPath)
                    .retrieve()
                    .body(String.class);
                var node = MAPPER.readTree(json);
                var encoded = node.get("content").asText();
                return new String(Base64.getMimeDecoder().decode(encoded));
            } catch (Exception e) {
                logger.warn("Failed to fetch source code for {}: {}", fullPath, e.getMessage());
                return "Source code not available: " + e.getMessage();
            }
        }
    }
}
