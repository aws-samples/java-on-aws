package com.example.ai.jvmanalyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.web.client.RestClient;

import java.util.Base64;

/**
 * Spring AI tool that fetches source code from a GitHub repository.
 * Enabled only when GITHUB_REPO_URL is set (e.g. https://api.github.com/repos/aws-samples/java-on-aws).
 * For private repos, set GITHUB_TOKEN to a PAT with contents:read scope.
 * Set GITHUB_REPO_PATH to the application root within the repo (e.g. apps/unicorn-store-spring).
 */
public class GitHubSourceCodeTool {

    private static final Logger logger = LoggerFactory.getLogger(GitHubSourceCodeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RestClient restClient;
    private final String repoPath;

    public GitHubSourceCodeTool(String repoUrl, String token, String repoPath) {
        var builder = RestClient.builder()
            .baseUrl(repoUrl)
            .defaultHeader("Accept", "application/vnd.github.v3+json")
            .defaultHeader("User-Agent", "ai-jvm-analyzer");
        if (token != null && !token.isBlank()) {
            builder.defaultHeader("Authorization", "token " + token);
        }
        this.restClient = builder.build();
        this.repoPath = (repoPath != null && !repoPath.isBlank()) ? repoPath.replaceAll("/$", "") : "";
    }

    @Tool(description = "Fetch a source code file from the application GitHub repository. " +
          "Provide the path relative to the application root, e.g. " +
          "src/main/java/com/example/MyClass.java — the repository base path is prepended automatically. " +
          "Use this to look up Java source files referenced in stack traces and thread dumps.")
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
