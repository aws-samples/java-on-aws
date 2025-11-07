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
import reactor.core.publisher.Flux;

import java.util.Base64;

@Service
public class DocumentChatService {
    private static final Logger logger = LoggerFactory.getLogger(DocumentChatService.class);

    private final ChatClient documentChatClient;
    private final ChatService chatService;

    @Value("${ai.agent.document.model}")
    private String documentModel;

    public static final String DOCUMENT_ANALYSIS_PROMPT = """
        Extract expense information from this document.

        Required fields:
        - Document Type: [RECEIPT, INVOICE, TICKET, BILL, OTHER]
        - Expense Type: [MEALS, ACCOMMODATION, TRANSPORTATION, OFFICE_SUPPLIES, OTHER]
        - Amount and Currency
        - Date: [YYYY-MM-DD]
        
        Category-specific details:
        - ACCOMMODATION: check-in/out dates, nights, rate per night, location
        - MEALS: contains alcohol (yes/no)
        - TRANSPORTATION: type, route or location
        
        Check against the Expense Policy and provide approval status with reasoning.
        If not an expense document, provide a brief summary.
        For missing information, state "I don't know".
        """;

    public DocumentChatService(ChatModel chatModel, ChatService chatService) {
        this.documentChatClient = ChatClient.builder(chatModel)
                .defaultSystem(DOCUMENT_ANALYSIS_PROMPT)
                .build();
        this.chatService = chatService;
    }

    public Flux<String> processDocument(String prompt, String fileBase64, String fileName) {
        logger.info("Processing document chat request - fileName: {}", fileName);

        return Flux.create(sink -> {
            // Step 1: Emit immediate feedback
            sink.next("Analyzing document...\n\n");
            
            // Step 2: Analyze document (blocking)
            String documentAnalysis = analyzeDocument(prompt, fileBase64, fileName);
            
            // Step 3: Stream the analysis result
            String additionalPrompt = documentAnalysis + "\n\n" +
                "Based on the extracted information, please provide a structured summary of the expense document including the following fields:\n" +
                "Add Amount in EUR: If original currency is EUR, use the original amount. " +
                "If original currency is not EUR, use available currency conversion tools to convert the original amount to EUR based on the document date. If conversion is not available, use current date. \n\n" +
                "After presenting the information, ask the user to confirm and offer to register the expense.";
            
            chatService.processChat(additionalPrompt)
                .subscribe(
                    chunk -> sink.next(chunk),
                    error -> sink.error(error),
                    () -> sink.complete()
                );
        });
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
