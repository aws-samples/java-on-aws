package com.example.agent;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test that performs a real Amazon Bedrock (Nova grounding) web-search call through
 * {@link WebGroundingTools}.
 *
 * <p>Double-guarded: named {@code *IT} (Failsafe / {@code mvn verify} only) and
 * {@link EnabledIfEnvironmentVariable} so it is skipped unless AWS credentials are available.
 * Requires Bedrock access to the Nova model in the resolved region.
 */
@EnabledIfEnvironmentVariable(named = "AWS_ACCESS_KEY_ID", matches = ".+")
class WebGroundingToolsIT {

    @Test
    void searchWeb_returnsGroundedAnswer() {
        WebGroundingTools tools = new WebGroundingTools("us.amazon.nova-2-lite-v1:0");
        try {
            String result = tools.searchWeb("What is the capital of France?");

            assertThat(result).isNotBlank();
            // The model should ground on the query; "Paris" is a stable expected token.
            assertThat(result).containsIgnoringCase("Paris");
        } finally {
            tools.close();
        }
    }
}
