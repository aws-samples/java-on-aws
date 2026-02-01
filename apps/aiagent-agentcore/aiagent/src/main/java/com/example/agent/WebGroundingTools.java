package com.example.agent;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import jakarta.annotation.PreDestroy;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.*;

@Service
public class WebGroundingTools {

	private static final Logger logger = LoggerFactory.getLogger(WebGroundingTools.class);

	private final BedrockRuntimeClient bedrockClient;

	private final String modelId;

	public WebGroundingTools(@Value("${app.ai.web-grounding.model:us.amazon.nova-2-lite-v1:0}") String modelId) {
		this.modelId = modelId;
		this.bedrockClient = BedrockRuntimeClient.builder().build();
		logger.info("WebGroundingTools: model={}", modelId);
	}

	@PreDestroy
	public void close() {
		if (bedrockClient != null) {
			bedrockClient.close();
		}
	}

	@Tool(description = "Search the web for current information. Use for news, real-time data, or facts needing verification.")
	public String searchWeb(@ToolParam(description = "Search query") String query) {
		logger.info("Web search: {}", query);
		try {
			var response = bedrockClient.converse(ConverseRequest.builder()
				.modelId(modelId)
				.messages(Message.builder().role(ConversationRole.USER).content(ContentBlock.fromText(query)).build())
				.toolConfig(ToolConfiguration.builder()
					.tools(software.amazon.awssdk.services.bedrockruntime.model.Tool
						.fromSystemTool(SystemTool.builder().name("nova_grounding").build()))
					.build())
				.build());

			return extractResponse(response);
		}
		catch (Exception e) {
			logger.error("Web search failed: {}", e.getMessage(), e);
			return "Web search failed. Try again later.";
		}
	}

	private String extractResponse(ConverseResponse response) {
		var result = new StringBuilder();
		var citations = new StringBuilder();

		if (response.output() != null && response.output().message() != null) {
			for (var block : response.output().message().content()) {
				if (block.text() != null) {
					result.append(block.text());
				}
				if (block.citationsContent() != null && block.citationsContent().citations() != null) {
					for (var citation : block.citationsContent().citations()) {
						if (citation.location() != null && citation.location().web() != null) {
							var url = citation.location().web().url();
							if (url != null && !url.isEmpty()) {
								citations.append("\n- ").append(url);
							}
						}
					}
				}
			}
		}

		if (result.isEmpty()) {
			return "No results found.";
		}
		if (!citations.isEmpty()) {
			result.append("\n\nSources:").append(citations);
		}
		return result.toString();
	}

}
