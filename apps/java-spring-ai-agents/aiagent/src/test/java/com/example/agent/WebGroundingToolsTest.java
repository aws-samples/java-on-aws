package com.example.agent;

import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.bedrockruntime.model.ContentBlock;
import software.amazon.awssdk.services.bedrockruntime.model.ConversationRole;
import software.amazon.awssdk.services.bedrockruntime.model.ConverseOutput;
import software.amazon.awssdk.services.bedrockruntime.model.ConverseResponse;
import software.amazon.awssdk.services.bedrockruntime.model.Message;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pure unit tests for {@link WebGroundingTools#extractResponse}. No AWS credentials required:
 * the Bedrock response is constructed in-memory and only the parsing/formatting logic is exercised.
 */
class WebGroundingToolsTest {

    @Test
    void extractResponse_withTextBlocks_concatenatesText() {
        ConverseResponse response = responseWith(
                ContentBlock.fromText("Paris is the capital of France. "),
                ContentBlock.fromText("It has about 2 million residents."));

        String result = WebGroundingTools.extractResponse(response);

        assertThat(result)
                .contains("Paris is the capital of France.")
                .contains("2 million residents");
    }

    @Test
    void extractResponse_withNoContent_returnsNoResults() {
        ConverseResponse empty = ConverseResponse.builder()
                .output(ConverseOutput.fromMessage(m -> m.role(ConversationRole.ASSISTANT)
                        .content(List.of())))
                .build();

        assertThat(WebGroundingTools.extractResponse(empty)).isEqualTo("No results found.");
    }

    @Test
    void extractResponse_withNullOutput_returnsNoResults() {
        ConverseResponse response = ConverseResponse.builder().build();

        assertThat(WebGroundingTools.extractResponse(response)).isEqualTo("No results found.");
    }

    private static ConverseResponse responseWith(ContentBlock... blocks) {
        Message message = Message.builder()
                .role(ConversationRole.ASSISTANT)
                .content(blocks)
                .build();
        return ConverseResponse.builder()
                .output(ConverseOutput.fromMessage(message))
                .build();
    }
}
