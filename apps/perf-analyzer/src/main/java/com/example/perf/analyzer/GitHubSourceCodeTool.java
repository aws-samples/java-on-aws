package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Base64;

/**
 * Spring AI @Tool: fetch source code from a GitHub repository via the
 * REST API.
 *
 * Singleton @Component, mirroring {@link PyroscopeTool}. Per-analysis
 * coordinates (repo, pathPrefix) are passed by the model on each call;
 * the analyzer surfaces the right values to the model through the prompt.
 *
 * The optional GitHub PAT for private repositories comes from the
 * GITHUB_TOKEN environment variable.
 */
@Component
public class GitHubSourceCodeTool {

    private static final Logger logger = LoggerFactory.getLogger(GitHubSourceCodeTool.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RestClient restClient;

    public GitHubSourceCodeTool(@Value("${GITHUB_TOKEN:}") String githubToken) {
        var builder = RestClient.builder()
            .baseUrl("https://api.github.com")
            .defaultHeader("Accept", "application/vnd.github.v3+json")
            .defaultHeader("User-Agent", "perf-analyzer");
        if (githubToken != null && !githubToken.isBlank()) {
            builder.defaultHeader("Authorization", "token " + githubToken);
        }
        this.restClient = builder.build();
    }

    @Tool(description = """
        Fetch a source code file from a GitHub repository.
        Parameters:
          repo        - "{owner}/{name}" (e.g. "aws-samples/java-on-aws").
          pathPrefix  - optional path prefix inside the repo for the
                        application root (e.g. "apps/unicorn-store-spring").
                        Pass an empty string if not applicable.
          filePath    - path relative to the application root, e.g.
                        "src/main/java/com/unicorn/store/service/UnicornService.java".
        Use this to look up Java source files referenced in stack traces,
        thread dumps, and JFR event summaries so recommendations can cite
        file paths and line numbers.
        """)
    public String fetchSourceCode(String repo, String pathPrefix, String filePath) {
        if (repo == null || repo.isBlank()) {
            return "Source code not available: repo not provided.";
        }
        var prefix = (pathPrefix == null || pathPrefix.isBlank())
            ? "" : pathPrefix.replaceAll("/$", "");
        var fullPath = prefix.isEmpty() ? filePath : prefix + "/" + filePath;
        var uri = "/repos/" + repo.replaceAll("/$", "") + "/contents/" + fullPath;
        try {
            var json = restClient.get()
                .uri(uri)
                .retrieve()
                .body(String.class);
            var node = MAPPER.readTree(json);
            var encoded = node.get("content").asText();
            return new String(Base64.getMimeDecoder().decode(encoded));
        } catch (Exception e) {
            logger.warn("Failed to fetch source code repo={} path={}: {}",
                repo, fullPath, e.getMessage());
            return "Source code not available: " + e.getMessage();
        }
    }
}
