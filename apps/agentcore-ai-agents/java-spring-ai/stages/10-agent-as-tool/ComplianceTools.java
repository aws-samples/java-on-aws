package com.example.agent;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springaicommunity.agentcore.artifacts.SessionConstants;
import org.springframework.ai.model.tool.internal.ToolCallReactiveContextHolder;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.http.nio.netty.NettyNioAsyncHttpClient;
import software.amazon.awssdk.services.bedrockagentcore.BedrockAgentCoreAsyncClient;
import software.amazon.awssdk.services.bedrockagentcore.model.HarnessContentBlock;
import software.amazon.awssdk.services.bedrockagentcore.model.HarnessConversationRole;
import software.amazon.awssdk.services.bedrockagentcore.model.InvokeHarnessRequest;
import software.amazon.awssdk.services.bedrockagentcore.model.InvokeHarnessResponseHandler;

/**
 * Agent as tool: asks the compliance auditor harness whether a trip or an expense complies with the policies.
 * Report links in the auditor's answer are moved to this agent's answer.
 */
@Component
public class ComplianceTools {

    private static final Logger logger = LoggerFactory.getLogger(ComplianceTools.class);
    // Report links of the auditor: "Report: <https://.../artifacts/...>", "Report: https://...", or a Markdown link [name](https://...)
    private static final Pattern REPORT_LINK =
        Pattern.compile("\\s*(?:Report:\\s*)?<?(?:!?\\[[^\\]]*\\]\\()?(https://[^\\s)>]+/artifacts/[^\\s)>]+)[)>]?");

    // >> The auditor harness from `application.properties`; empty means no tool
    private final String harnessArn;
    // <<
    // >> InvokeHarness streams events, so it needs the asynchronous client; a check with a report takes about a minute
    private final BedrockAgentCoreAsyncClient agentCore = BedrockAgentCoreAsyncClient.builder()
        .httpClientBuilder(NettyNioAsyncHttpClient.builder().readTimeout(Duration.ofMinutes(5)))
        .build();
    // <<
    private final Map<String, List<String>> reportLinks = new ConcurrentHashMap<>();

    public ComplianceTools(@Value("${app.auditor.harness-arn}") String harnessArn) {
        this.harnessArn = harnessArn;
    }

    public boolean enabled() {
        return !harnessArn.isEmpty();
    }

    @Tool(name = "check_compliance", description = """
        Ask the compliance auditor whether a planned trip or an expense complies with the company travel and \
        expense policies. Returns COMPLIANT or NOT COMPLIANT with the rules that apply. When the user wants a \
        downloadable audit report, ask for one in the request; its link is added to the answer automatically.""")
    public String checkCompliance(
            @ToolParam(description = "The trip or expense to check, with all known details (route, travel class, dates, amount, currency)")
            String request) {
        String sessionId = ToolCallReactiveContextHolder.getContext()
            .getOrDefault(SessionConstants.SESSION_ID_KEY, SessionConstants.DEFAULT_SESSION_ID);
        return forwardLinks(askAuditor(request), sessionId);
    }

    /** Report links for this conversation; `ChatService` appends them after the answer. */
    public List<String> takeReportLinks(String sessionId) {
        List<String> links = reportLinks.remove(sessionId);
        return links == null ? List.of() : links;
    }

    private String askAuditor(String request) {
        // >> InvokeHarness runs the auditor's agent loop on AgentCore; one session per check (at least 33 characters)
        InvokeHarnessRequest invocation = InvokeHarnessRequest.builder()
            .harnessArn(harnessArn)
            .runtimeSessionId(UUID.randomUUID().toString())
            .messages(m -> m.role(HarnessConversationRole.USER).content(HarnessContentBlock.fromText(request)))
            .build();
        // <<
        StringBuilder answer = new StringBuilder();
        // >> The answer arrives as a stream of events; collect the text deltas
        InvokeHarnessResponseHandler handler = InvokeHarnessResponseHandler.builder()
            .subscriber(InvokeHarnessResponseHandler.Visitor.builder()
                .onContentBlockDelta(event -> {
                    if (event.delta() != null && event.delta().text() != null) {
                        answer.append(event.delta().text());
                    }
                })
                .build())
            .build();
        // <<
        try {
            agentCore.invokeHarness(invocation, handler).join();
        } catch (Exception e) {
            logger.error("Compliance auditor call failed", e);
            return "Compliance auditor error: " + (e.getCause() != null ? e.getCause().getMessage() : e.getMessage());
        }
        return answer.toString();
    }

    // >> Move the auditor's report links to this agent's answer, so the model doesn't have to copy long URLs
    private String forwardLinks(String answer, String sessionId) {
        Matcher matcher = REPORT_LINK.matcher(answer);
        List<String> links = new ArrayList<>();
        while (matcher.find()) {
            links.add(matcher.group(1));
        }
        if (links.isEmpty()) {
            return answer;
        }
        reportLinks.computeIfAbsent(sessionId, k -> new ArrayList<>()).addAll(links);
        return matcher.replaceAll("") + "\n\n(The download link for the report is appended after your answer.)";
    }
    // <<
}
