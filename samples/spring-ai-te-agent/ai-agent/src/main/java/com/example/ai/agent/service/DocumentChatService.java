package com.example.ai.agent.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.model.tool.ToolCallingChatOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.MediaTypeFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.MimeType;
import org.springframework.util.MimeTypeUtils;

import java.util.Base64;

@Service
public class DocumentChatService {
    private static final Logger logger = LoggerFactory.getLogger(DocumentChatService.class);

    private final ChatClient documentChatClient;
    private final ChatService chatService;

    @Value("${ai.agent.document.model}")
    private String documentModel;

    public static final String DOCUMENT_ANALYSIS_PROMPT = """
        Analyze this document and extract expense information if possible.

        ## Core Information
        - Document Type: [RECEIPT, INVOICE, TICKET, BILL, OTHER]
        - Expense Type: [MEALS, TRANSPORTATION, OFFICE_SUPPLIES, ACCOMMODATION, OTHER]
        - Amount: [numerical value only]
        - Currency: [code only, e.g., USD, EUR]
        - Date: [YYYY-MM-DD format]

        ## Category-Specific Details
        For ACCOMMODATION:
        - Check-in/out Dates
        - Nights
        - Price per Night
        - Breakfast Included [Yes/No]
        - Location

        For MEALS:
        - Contains Alcohol [Yes/No]

        For TRANSPORTATION:
        - Type [car, train, plane, etc.]
        - Location

        ## Policy Compliance
        Check the expense against the company's Travel and Expense Policy and provide:
        - Status: [APPROVED, REQUIRES_MANAGER_APPROVAL, REQUIRES_DIRECTOR_APPROVAL, REQUIRES_EXECUTIVE_APPROVAL, POLICY_VIOLATION]
        - Reason: [brief explanation]
        - Policy Reference: Specifically mention which section of the Travel and Expense Policy applies

        For any field where information is missing or unclear, state "I don't know".
        Double-check all monetary values for accuracy.

        ## Non-Expense Documents
        If the document cannot be recognized as an expense document (receipt, invoice, bill, ticket, etc.),
        do not attempt to extract expense information. Instead:
        1. Clearly state that this does not appear to be an expense document
        2. Provide a concise summary of the document's content in 2-3 paragraphs
        3. Describe the key information, purpose, and type of document it appears to be
        """;

    public DocumentChatService(ChatModel chatModel, ChatService chatService) {
        this.documentChatClient = ChatClient.builder(chatModel)
                .defaultSystem(DOCUMENT_ANALYSIS_PROMPT)
                .build();
        this.chatService = chatService;
    }

    public String processDocument(String prompt, String fileBase64, String fileName) {
        logger.info("Processing document chat request - fileName: {}", fileName);

        // Step 1: Analyze document with document model
        String documentAnalysis = analyzeDocument(prompt, fileBase64, fileName);

        // Step 2: Send analysis to ChatService with additional prompt
        String additionalPrompt = documentAnalysis + "\n\n" +
            "Based on the extracted information, please provide a structured summary of the expense document including the following fields:\n" +
            "Add Amount in EUR: If original currency is EUR, use the original amount. " +
            "If original currency is not EUR, use available currency conversion tools to convert the original amount to EUR based on the document date. If conversion is not available, use current date. \n\n" +
            "After presenting the information, ask the user to confirm and offer to register the expense.";

        return chatService.processChat(additionalPrompt);
    }

    private String analyzeDocument(String prompt, String fileBase64, String fileName) {
        MimeType mimeType = determineMimeType(fileName);
        byte[] fileData = Base64.getDecoder().decode(fileBase64);
        ByteArrayResource resource = new ByteArrayResource(fileData);

        final String userPrompt = (prompt != null && !prompt.trim().isEmpty())
                ? prompt
                : "Analyze this document";

        try {
            var chatResponse = documentChatClient
                    .prompt()
                    .options(ToolCallingChatOptions.builder()
                            .model(documentModel)
                            .build())
                    .user(userSpec -> {
                        userSpec.text(userPrompt);
                        userSpec.media(mimeType, resource);
                    })
                    .call().chatResponse();

            return (chatResponse != null) ? chatResponse.getResult().getOutput().getText() : "I don't know - no response received.";
        } catch (Exception e) {
            logger.error("Error analyzing document", e);
            return "I don't know - there was an error analyzing the document.";
        }
    }

    private MimeType determineMimeType(String fileName) {
        if (fileName != null && !fileName.trim().isEmpty()) {
            MediaType mediaType = MediaTypeFactory.getMediaType(fileName)
                    .orElse(MediaType.APPLICATION_OCTET_STREAM);
            return new MimeType(mediaType.getType(), mediaType.getSubtype());
        }
        return MimeTypeUtils.APPLICATION_OCTET_STREAM;
    }

}
