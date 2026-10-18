package com.example.agent;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Objects;

import org.springaicommunity.agentcore.artifacts.SessionConstants;
import org.springaicommunity.agentcore.context.AgentCoreContext;
import org.springaicommunity.agentcore.context.AgentCoreHeaders;
import org.springframework.ai.model.tool.internal.ToolCallReactiveContextHolder;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import reactor.util.context.ContextView;
import software.amazon.awssdk.services.bedrockagentcore.BedrockAgentCoreClient;
import software.amazon.awssdk.services.bedrockagentcore.model.GetResourceOauth2TokenResponse;
import software.amazon.awssdk.services.bedrockagentcore.model.Oauth2FlowType;
import software.amazon.awssdk.services.bedrockagentcore.model.UserIdentifier;
import tools.jackson.databind.json.JsonMapper;

/**
 * The corporate calendar, read on behalf of the signed-in user with a token from the AgentCore Identity token vault
 * (USER_FEDERATION, 3LO).
 */
@Component
public class CalendarTools {

    /** Reactor context key for the request context: the tool reads the request headers from it. */
    static final String REQUEST_KEY = "agentcore.request";
    private static final String LOCAL_WORKLOAD = "aiagent-local";
    private static final JsonMapper JSON = JsonMapper.builder().build();

    private final BedrockAgentCoreClient identity = BedrockAgentCoreClient.create();
    private final HttpClient http = HttpClient.newHttpClient();
    private final String calendarUrl;
    private final String returnUrl;

    // >> Where AgentCore sends the browser after the consent: the UI's callback page
    public CalendarTools(@Value("${app.calendar.url}") String calendarUrl,
                         @Value("${app.calendar.return-url}") String returnUrl) {
    // <<
        this.calendarUrl = calendarUrl;
        this.returnUrl = returnUrl;
    }

    public boolean enabled() {
        return !calendarUrl.isEmpty();
    }

    @Tool(name = "get_calendar_events", description = """
        Read the user's events from the corporate calendar: meetings, trips, and conferences with date, time, and \
        location. Use it to check whether the user is free for a trip or to find the dates of an event.""")
    public String getCalendarEvents() throws Exception {
        ContextView context = ToolCallReactiveContextHolder.getContext();
        AgentCoreContext request = context.get(REQUEST_KEY);
        String userId = userId(context.getOrDefault(SessionConstants.SESSION_ID_KEY, SessionConstants.DEFAULT_SESSION_ID));
        // >> USER_FEDERATION (3LO): a token for this user from the token vault, or a link for the user's consent
        GetResourceOauth2TokenResponse token = identity.getResourceOauth2Token(b -> b
            .workloadIdentityToken(workloadToken(request, userId))
            .resourceCredentialProviderName("calendar-provider")
            .scopes("openid", "calendar/read")
            .oauth2Flow(Oauth2FlowType.USER_FEDERATION)
            .resourceOauth2ReturnUrl(returnUrl));
        // <<
        if (token.accessToken() == null) {
            return "The user has not connected the corporate calendar yet. Give the user this link to sign in "
                + "and ask them to send the question again afterwards: " + token.authorizationUrl();
        }
        // >> Call the calendar API with the user's token, as the user
        HttpResponse<String> response = http.send(HttpRequest.newBuilder(URI.create(calendarUrl + "/events"))
                .header("Authorization", "Bearer " + token.accessToken())
                .timeout(Duration.ofSeconds(10))
                .build(),
            HttpResponse.BodyHandlers.ofString());
        return JSON.readTree(response.body()).get("events").toString();
        // <<
    }

    /** Bind the consent session from the callback page to the user who started it. */
    public void completeAuthorization(String sessionUri, String conversationId, AgentCoreContext request) {
        // >> The same user as for the workload access token: the user's JWT on Runtime, the user ID locally
        String authorization = Objects.requireNonNullElse(request.getHeader(AgentCoreHeaders.AUTHORIZATION), "");
        UserIdentifier user = runtimeWorkloadToken(request) != null
            ? UserIdentifier.fromUserToken(authorization.replaceFirst("^Bearer ", ""))
            : UserIdentifier.fromUserId(userId(conversationId));
        identity.completeResourceTokenAuth(b -> b.sessionUri(sessionUri).userIdentifier(user));
        // <<
    }

    private String workloadToken(AgentCoreContext request, String userId) {
        // >> On AgentCore Runtime the request carries a workload access token for the signed-in user
        String token = runtimeWorkloadToken(request);
        if (token != null) {
            return token;
        }
        // <<
        // >> Locally, the application gets one for the user ID from its own workload identity
        return identity.getWorkloadAccessTokenForUserId(b -> b.workloadName(LOCAL_WORKLOAD).userId(userId))
            .workloadAccessToken();
        // <<
    }

    private static String runtimeWorkloadToken(AgentCoreContext request) {
        String token = request.getHeader(AgentCoreHeaders.WORKLOAD_ACCESS_TOKEN);
        return token == null || token.isBlank() ? null : token;
    }

    /** The user ID part of the conversation ID (`userId:sessionId`): the Cognito `sub` with a JWT. */
    private static String userId(String conversationId) {
        return conversationId.split(":")[0];
    }
}
