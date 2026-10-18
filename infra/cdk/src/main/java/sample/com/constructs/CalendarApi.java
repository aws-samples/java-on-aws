package sample.com.constructs;

import io.github.cdklabs.cdknag.NagPackSuppression;
import io.github.cdklabs.cdknag.NagSuppressions;
import software.amazon.awscdk.Aws;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.cognito.CfnUserPoolClient;
import software.amazon.awscdk.services.cognito.CognitoDomainOptions;
import software.amazon.awscdk.services.cognito.ManagedLoginVersion;
import software.amazon.awscdk.services.cognito.PasswordPolicy;
import software.amazon.awscdk.services.cognito.ResourceServerScope;
import software.amazon.awscdk.services.cognito.ResourceServerScopeProps;
import software.amazon.awscdk.services.cognito.UserPool;
import software.amazon.awscdk.services.cognito.UserPoolDomain;
import software.amazon.awscdk.services.cognito.UserPoolDomainOptions;
import software.amazon.awscdk.services.cognito.UserPoolResourceServer;
import software.amazon.awscdk.services.cognito.UserPoolResourceServerOptions;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.FunctionUrl;
import software.amazon.awscdk.services.lambda.FunctionUrlAuthType;
import software.amazon.awscdk.services.lambda.FunctionUrlOptions;
import software.amazon.awscdk.services.lambda.Runtime;
import software.amazon.awscdk.services.secretsmanager.ISecret;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.constructs.Construct;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * Corporate calendar of the agentcore-ai-agents workshop (AgentCore Identity, 3LO):
 * - Cognito user pool {prefix}-calendar-pool as the calendar's identity provider: domain
 *   {prefix}-calendar-<account> (classic hosted UI), resource server "calendar" with scope
 *   calendar/read, app client "agentcore" with a secret (the participant sets its callback URL
 *   to the AgentCore credential provider's callback), users alice and bob with the IDE password
 * - Lambda {prefix}-calendar-api (apps/agentcore-ai-agents/calendar-api/handler.py, inline code)
 *   behind a public function URL; the handler
 *   checks the bearer token with the pool's userInfo endpoint
 * - SSM parameters {prefix}-calendar-url, {prefix}-calendar-pool-id, {prefix}-calendar-client-id
 */
public class CalendarApi extends Construct {

    private final UserPool userPool;
    private final Function function;

    public static class CalendarApiProps {
        private String prefix = "workshop";
        private ISecret passwordSecret;
        private List<String> usernames = List.of("alice", "bob");

        public static CalendarApiProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private final CalendarApiProps props = new CalendarApiProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            /** Secret with a JSON "password" key (the IDE password): the users' password. */
            public Builder passwordSecret(ISecret passwordSecret) { props.passwordSecret = passwordSecret; return this; }
            public Builder usernames(List<String> usernames) { props.usernames = List.copyOf(usernames); return this; }
            public CalendarApiProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
        public ISecret getPasswordSecret() { return passwordSecret; }
        public List<String> getUsernames() { return usernames; }
    }

    public CalendarApi(final Construct scope, final String id, final CalendarApiProps props) {
        super(scope, id);
        String prefix = props.getPrefix();

        // Identity provider of the calendar (a second pool next to the participant's aiagent-user-pool)
        this.userPool = UserPool.Builder.create(this, "UserPool")
            .userPoolName(prefix + "-calendar-pool")
            .selfSignUpEnabled(false)
            .passwordPolicy(PasswordPolicy.builder()
                .minLength(8)
                .requireLowercase(false)
                .requireUppercase(false)
                .requireDigits(false)
                .requireSymbols(false)
                .build())
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        UserPoolDomain domain = userPool.addDomain("Domain", UserPoolDomainOptions.builder()
            .cognitoDomain(CognitoDomainOptions.builder()
                .domainPrefix(prefix + "-calendar-" + Aws.ACCOUNT_ID)
                .build())
            .managedLoginVersion(ManagedLoginVersion.CLASSIC_HOSTED_UI)
            .build());

        UserPoolResourceServer resourceServer = userPool.addResourceServer("ResourceServer",
            UserPoolResourceServerOptions.builder()
                .identifier("calendar")
                .userPoolResourceServerName("calendar")
                .scopes(List.of(new ResourceServerScope(ResourceServerScopeProps.builder()
                    .scopeName("read")
                    .scopeDescription("Read calendar events")
                    .build())))
                .build());

        // L1 client: the same settings the participant's update-user-pool-client call sets again
        CfnUserPoolClient client = CfnUserPoolClient.Builder.create(this, "AgentCoreClient")
            .userPoolId(userPool.getUserPoolId())
            .clientName("agentcore")
            .generateSecret(true)
            .allowedOAuthFlows(List.of("code"))
            .allowedOAuthScopes(List.of("openid", "calendar/read"))
            .allowedOAuthFlowsUserPoolClient(true)
            .supportedIdentityProviders(List.of("COGNITO"))
            .callbackUrLs(List.of("https://example.com/set-by-the-participant"))
            .build();
        client.getNode().addDependency(resourceServer);

        // Users alice and bob, password = IDE password
        Role usersRole = Role.Builder.create(this, "UsersRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")))
            .build();
        usersRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("cognito-idp:AdminGetUser", "cognito-idp:AdminCreateUser", "cognito-idp:AdminSetUserPassword"))
            .resources(List.of(userPool.getUserPoolArn()))
            .build());
        props.getPasswordSecret().grantRead(usersRole);
        var usersFunction = new Lambda(this, "Users",
            "/lambda/calendar-users.py", prefix + "-calendar-users", Duration.minutes(2), usersRole);
        var users = CustomResource.Builder.create(this, "UsersResource")
            .serviceToken(usersFunction.getFunction().getFunctionArn())
            .properties(Map.of(
                "UserPoolId", userPool.getUserPoolId(),
                "PasswordSecretArn", props.getPasswordSecret().getSecretArn(),
                "Usernames", props.getUsernames()))
            .build();
        users.getNode().addDependency(usersRole);

        // Calendar API: GET /events with a bearer token of the calendar pool
        Role apiRole = Role.Builder.create(this, "FunctionRole")
            .roleName(prefix + "-calendar-api-role")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")))
            .build();
        this.function = Function.Builder.create(this, "Function")
            .functionName(prefix + "-calendar-api")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.handler")
            .code(Code.fromInline(loadFile(Path.of("..", "..", "apps", "agentcore-ai-agents", "calendar-api", "handler.py"))))
            .timeout(Duration.seconds(10))
            .role(apiRole)
            .environment(Map.of("USERINFO_URL", domain.baseUrl() + "/oauth2/userInfo"))
            .build();
        // Public URL; CDK adds the lambda:InvokeFunctionUrl and lambda:InvokeFunction (via URL) permissions
        FunctionUrl functionUrl = function.addFunctionUrl(FunctionUrlOptions.builder()
            .authType(FunctionUrlAuthType.NONE)
            .build());

        // Function URL without the trailing slash: https://<id>.lambda-url.<region>.on.aws
        String calendarUrl = "https://" + Fn.select(2, Fn.split("/", functionUrl.getUrl()));
        StringParameter.Builder.create(this, "UrlParameter")
            .parameterName(prefix + "-calendar-url")
            .description("Corporate calendar API URL (agentcore-ai-agents workshop)")
            .stringValue(calendarUrl)
            .build();
        StringParameter.Builder.create(this, "PoolIdParameter")
            .parameterName(prefix + "-calendar-pool-id")
            .description("Corporate calendar user pool ID (agentcore-ai-agents workshop)")
            .stringValue(userPool.getUserPoolId())
            .build();
        StringParameter.Builder.create(this, "ClientIdParameter")
            .parameterName(prefix + "-calendar-client-id")
            .description("Corporate calendar app client for AgentCore Identity (agentcore-ai-agents workshop)")
            .stringValue(client.getRef())
            .build();

        NagSuppressions.addResourceSuppressions(userPool, List.of(
            NagPackSuppression.builder().id("AwsSolutions-COG1")
                .reason("Workshop test users sign in with the generated 32-character IDE password").build(),
            NagPackSuppression.builder().id("AwsSolutions-COG2")
                .reason("Workshop test users of an ephemeral calendar do not need MFA").build(),
            NagPackSuppression.builder().id("AwsSolutions-COG3")
                .reason("Ephemeral workshop pool does not need threat protection").build(),
            NagPackSuppression.builder().id("AwsSolutions-COG8")
                .reason("Ephemeral workshop pool stays on the default feature plan").build()), true);
    }

    /** A file of the workshop code (cdk synth runs in infra/cdk). */
    private String loadFile(Path path) {
        try {
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public UserPool getUserPool() {
        return userPool;
    }

    public Function getFunction() {
        return function;
    }
}
