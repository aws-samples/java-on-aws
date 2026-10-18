package com.example.agent;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;

import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springframework.ai.chat.client.ChatClientRequest;
import org.springframework.ai.chat.client.ChatClientResponse;
import org.springframework.ai.chat.client.advisor.api.AdvisorChain;
import org.springframework.ai.chat.client.advisor.api.BaseAdvisor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.document.Document;
import software.amazon.awssdk.services.bedrockagentcorecontrol.BedrockAgentCoreControlClient;
import software.amazon.awssdk.services.bedrockagentcorecontrol.model.ComponentConfiguration;

/**
 * Sets the system prompt from the AgentCore configuration bundle before every model call: the latest version, or
 * the version that an A/B test assigns to the session.
 */
@Component
public class PromptConfig implements BaseAdvisor {

    /** Advisor parameter with the request's W3C `baggage` header. */
    static final String BAGGAGE = "baggage";

    private final BedrockAgentCoreControlClient control = BedrockAgentCoreControlClient.create();
    private final String bundleId;
    private final Map<String, String> versionPrompts = new ConcurrentHashMap<>();
    private volatile Instant readAt = Instant.EPOCH;
    private volatile String latestPrompt;

    public PromptConfig(@Value("${app.config-bundle.id}") String bundleId) {
        this.bundleId = bundleId;
    }

    public boolean enabled() {
        return !bundleId.isEmpty();
    }

    static String baggage(AgentCoreContext context) {
        return Objects.requireNonNullElse(context.getHeader(BAGGAGE), "");
    }

    @Override
    public ChatClientRequest before(ChatClientRequest request, AdvisorChain advisorChain) {
        // >> During an A/B test the Gateway passes the session's variant (a bundle version) as W3C baggage
        String prompt = variantPrompt((String) request.context().getOrDefault(BAGGAGE, ""));
        if (prompt == null) {
            prompt = latestPrompt();
        }
        // <<
        if (prompt == null) {
            return request;
        }
        // >> Replace the system prompt of this call; the other advisors add their context afterwards
        return request.mutate().prompt(request.prompt().augmentSystemMessage(prompt)).build();
        // <<
    }

    @Override
    public ChatClientResponse after(ChatClientResponse response, AdvisorChain advisorChain) {
        return response;
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }

    private String latestPrompt() {
        // >> The latest version of the bundle, read at most once a minute
        if (Duration.between(readAt, Instant.now()).toSeconds() > 60) {
            latestPrompt = systemPrompt(control.getConfigurationBundle(b -> b.bundleId(bundleId)).components());
            readAt = Instant.now();
        }
        // <<
        return latestPrompt;
    }

    private String variantPrompt(String baggage) {
        Map<String, String> entries = new HashMap<>();
        for (String entry : baggage.split(",")) {
            String[] keyValue = entry.split(";")[0].split("=", 2);
            if (keyValue.length == 2) {
                entries.put(keyValue[0].strip(), URLDecoder.decode(keyValue[1].strip(), StandardCharsets.UTF_8));
            }
        }
        String arn = entries.get("aws.agentcore.configbundle_arn");
        String version = entries.get("aws.agentcore.configbundle_version");
        if (arn == null || version == null) {
            return null;
        }
        return versionPrompts.computeIfAbsent(version, v -> systemPrompt(control.getConfigurationBundleVersion(
            b -> b.bundleId(arn.substring(arn.lastIndexOf('/') + 1)).versionId(v)).components()));
    }

    /** `system_prompt` of the bundle's component (one component per runtime). */
    private static String systemPrompt(Map<String, ComponentConfiguration> components) {
        return components.values().stream().findFirst()
            .map(ComponentConfiguration::configuration)
            .filter(Document::isMap)
            .map(configuration -> configuration.asMap().get("system_prompt"))
            .filter(prompt -> prompt != null && prompt.isString())
            .map(Document::asString)
            .orElse(null);
    }
}
