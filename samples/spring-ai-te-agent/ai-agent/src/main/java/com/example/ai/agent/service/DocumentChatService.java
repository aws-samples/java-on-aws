package com.example.ai.agent.service;

import com.example.ai.agent.model.ChatRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.model.tool.ToolCallingChatOptions;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class DocumentChatService {
    private static final Logger logger = LoggerFactory.getLogger(DocumentChatService.class);

    private final ChatClient documentChatClient;
    private final ChatService chatService;

    @Value("${ai.agent.document.model}")
    private String documentModel;

    public DocumentChatService(ChatModel chatModel, ChatService chatService) {
        this.documentChatClient = ChatClient.builder(chatModel)
                .defaultSystem(Prompts.DOCUMENT_ANALYSIS_PROMPT)
                .build();
        this.chatService = chatService;
    }

    public String processChat(ChatRequest request) {
        logger.info("Processing document chat request - fileName: {}", request.fileName());

        // Step 1: Analyze document with document model
        String documentAnalysis = analyzeDocument(request);

        // Step 2: Send analysis to ChatService with additional prompt
        String additionalPrompt = documentAnalysis + "\n\n" +
            "Based on the extracted information, please provide a structured summary of the expense document including the following fields:\n" +
            "Add Amount in EUR: If original currency is EUR, use the original amount. " +
            "If original currency is not EUR, use available currency conversion tools to convert the original amount to EUR based on the document date. If conversion is not available, use current date. \n\n" +
            "After presenting the information, ask the user to confirm and offer to register the expense.";

        return chatService.processChat(new ChatRequest(additionalPrompt, null, null));
    }

    private String analyzeDocument(ChatRequest request) {
        ChatRequest.FileResource fileResource = request.buildFileResource();
        final String userPrompt = request.hasPrompt()
                ? request.prompt()
                : "Analyze this document";

        try {
            var chatResponse = documentChatClient
                    .prompt()
                    .options(ToolCallingChatOptions.builder()
                            .model(documentModel)
                            .build())
                    .user(userSpec -> {
                        userSpec.text(userPrompt);
                        userSpec.media(fileResource.mimeType(), fileResource.resource());
                    })
                    .call().chatResponse();

            return (chatResponse != null) ? chatResponse.getResult().getOutput().getText() : "I don't know - no response received.";
        } catch (Exception e) {
            logger.error("Error analyzing document", e);
            return "I don't know - there was an error analyzing the document.";
        }
    }

}
