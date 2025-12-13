package sample.com.constructs;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.lambda.Code;
import software.amazon.awscdk.services.lambda.Function;
import software.amazon.awscdk.services.lambda.Runtime;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Reusable Lambda construct for consistent function creation
 */
public class Lambda extends Construct {
    private final Function function;

    public static class LambdaProps {
        private String functionName;
        private Duration timeout = Duration.minutes(5);
        private Role role;

        public static LambdaProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private LambdaProps props = new LambdaProps();

            public Builder functionName(String functionName) { props.functionName = functionName; return this; }
            public Builder timeout(Duration timeout) { props.timeout = timeout; return this; }
            public Builder role(Role role) { props.role = role; return this; }

            public LambdaProps build() { return props; }
        }

        // Getters
        public String getFunctionName() { return functionName; }
        public Duration getTimeout() { return timeout; }
        public Role getRole() { return role; }
    }

    public Lambda(final Construct scope, final String id, final String filePath, final String functionName, final Duration timeout, final Role role) {
        this(scope, id, LambdaProps.builder()
            .functionName(functionName)
            .timeout(timeout)
            .role(role)
            .build(), filePath);
    }

    public Lambda(final Construct scope, final String id, final LambdaProps props, final String filePath) {
        super(scope, id);

        this.function = Function.Builder.create(this, "Function")
            .runtime(Runtime.PYTHON_3_13)
            .handler("index.lambda_handler")
            .code(Code.fromInline(loadFile(filePath)))
            .timeout(props.getTimeout())
            .functionName(props.getFunctionName())
            .role(props.getRole())
            .build();
    }

    public Function getFunction() {
        return function;
    }

    /**
     * Helper method to load file content from resources
     */
    private String loadFile(String filePath) {
        try {
            return Files.readString(Path.of(getClass().getResource(filePath).getPath()));
        } catch (IOException e) {
            throw new RuntimeException("Failed to load file " + filePath, e);
        }
    }
}