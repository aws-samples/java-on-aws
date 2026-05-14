package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.web.client.RestClient;

import java.util.Base64;

/**
 * Spring AI @Tool: fetch source code from a GitHub repository via the
 * REST API.
 *
 * The repo coordinates are per-analysis — the target workload advertises
 * them via the pod annotation {@code perf-profile/github-repo} (or the
 * ECS task tag {@code perf-profile:github-repo}). The analyzer constructs
 * a fresh instance each request, picking up whichever workload's repo
 * coordinates the current analysis context carries.
 *
 * Compare {@link PyroscopeTool}, which is a top-level @Component because
 * {@link AnalysisService} also invokes it directly for the pre-fetched
 * prompt sections.
 */
public class GitHubSourceCodeTool {

    private static final Logger logger = LoggerFactory.getLogger(GitHubSourceCodeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RestClient restClient;
    private final String repoPath;

    /**
     * @param repo   "{owner}/{name}" (e.g. "aws-samples/java-on-aws")
     * @param path   optional path-prefix inside the repo (e.g. "apps/unicorn-store-spring")
     * @param token  optional GitHub PAT for private repos
     */
    public GitHubSourceCodeTool(String repo, String path, String token) {
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
