package com.example.perf.optimizer.explain;

import com.example.perf.optimizer.catalog.Finding;
import com.example.perf.optimizer.facts.Facts;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Turns one computed {@link Finding} into an {@link Explanation}. The model
 * (Bedrock via Spring AI, temperature 0, structured output) writes ONLY the
 * rationale and expected-outcome prose; the artifact, apply command, evidence
 * lines and learn-more link are produced deterministically in Java. So the model
 * can never change a computed value or a golden Dockerfile — it explains, Java
 * computes. Grounded on the bundled {@code kb/*.md} (and a Bedrock KB when one is
 * configured), mirroring the legacy tool.
 */
@Component
public class Explainer {

    private static final Logger logger = LoggerFactory.getLogger(Explainer.class);
    private static final ObjectMapper JSON = new ObjectMapper();

    private static final String SYSTEM_PROMPT = """
        You explain a SINGLE, already-computed Kubernetes/JVM optimization finding to
        an engineer. Hard rules:
          - NO preamble. Do not restate the task or say "here is".
          - Cite ONLY the evidence and computed values provided. NEVER invent or change
            a number, JDK version, base image, JVM flag, or Linux capability.
          - The requests/limits, GC, and startup levers were computed by code from
            measured facts — treat them as fixed. Do not propose different values.
          - NEVER recommend G1GC on a <= 1 vCPU / small-heap container; SerialGC is correct.
          - Runtime is Amazon Corretto / Azul Zulu JDK 25, Spring Boot 4.1.
          - Be concrete and brief. 'rationale' = why this finding matters and why the
            computed fix is right (2-4 sentences). 'expectedOutcome' = what the engineer
            should observe after applying + re-running analyze (qualitative; the real
            numbers come from the re-measure).
        """;

    private final ChatClient.Builder chatClientBuilder;
    private final ObjectProvider<VectorStore> vectorStoreProvider;
    private final TemplateRenderer renderer;
    private volatile ChatClient chatClient;

    /** Model output — Java assembles the rest of the Explanation around it. */
    public record ModelExplanation(String rationale, String expectedOutcome) {}

    public Explainer(@Lazy ChatClient.Builder chatClientBuilder,
                     ObjectProvider<VectorStore> vectorStoreProvider,
                     TemplateRenderer renderer) {
        this.chatClientBuilder = chatClientBuilder;
        this.vectorStoreProvider = vectorStoreProvider;
        this.renderer = renderer;
    }

    public Explanation explain(String service, Finding finding, Facts facts) {
        var artifact = renderer.render(finding, facts);
        var applyCommand = ApplyCommand.forFinding(finding, facts);
        var evidenceLines = evidenceLines(finding);

        ModelExplanation model;
        try {
            model = chat().prompt()
                .user(userPrompt(service, finding, artifact, evidenceLines))
                .call()
                .entity(ModelExplanation.class);
        } catch (Exception e) {
            logger.warn("explain model call failed for {}: {}", finding.id(), e.getMessage());
            model = new ModelExplanation(
                "(model explanation unavailable; the computed artifact below is authoritative)", "");
        }

        return new Explanation(finding.id(),
            model == null ? "" : model.rationale(),
            evidenceLines, artifact, applyCommand,
            model == null ? "" : model.expectedOutcome(),
            finding.learnMore());
    }

    private static List<String> evidenceLines(Finding finding) {
        var lines = new ArrayList<>(finding.evidence());
        finding.computed().forEach((k, v) -> lines.add("computed " + k + " = " + v));
        return lines;
    }

    private String userPrompt(String service, Finding finding, String artifact, List<String> evidenceLines) {
        String findingJson;
        try {
            findingJson = JSON.writerWithDefaultPrettyPrinter().writeValueAsString(finding);
        } catch (Exception e) {
            findingJson = finding.toString();
        }
        return """
            ## Finding (computed by code — fixed)
            service: %s
            %s

            ## Measured evidence + computed values (cite only these)
            %s

            ## Ready-to-apply artifact (rendered by code — describe it, do NOT modify it)
            ```
            %s
            ```

            ## Reference (use verbatim; do not invent tags/flags)
            %s
            """.formatted(service, findingJson, String.join("\n", evidenceLines), artifact, kbSlice(finding.kb()));
    }

    /** The KB doc this finding declares (catalog {@code kb:}), injected as grounding. */
    private static String kbSlice(String kbDoc) {
        if (kbDoc == null || kbDoc.isBlank()) {
            return "";
        }
        try {
            return new ClassPathResource("kb/" + kbDoc).getContentAsString(StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    private ChatClient chat() {
        if (chatClient == null) {
            synchronized (this) {
                if (chatClient == null) {
                    var b = chatClientBuilder
                        .defaultSystem(SYSTEM_PROMPT)
                        .defaultOptions(ChatOptions.builder().temperature(0.0));
                    var vs = vectorStoreProvider.getIfAvailable();
                    if (vs != null) {
                        b = b.defaultAdvisors(QuestionAnswerAdvisor.builder(vs).build());
                        logger.info("Explainer KB grounding ENABLED");
                    }
                    chatClient = b.build();
                }
            }
        }
        return chatClient;
    }
}
