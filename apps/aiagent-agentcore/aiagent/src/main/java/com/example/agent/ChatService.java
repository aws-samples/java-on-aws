package com.example.agent;

// Core Spring AI
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

// Memory
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.ChatMemoryRepository;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;

// Knowledge Base
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.vectorstore.VectorStore;

// Common
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import java.util.ArrayList;
import java.util.List;

@Service
public class ChatService {

	private static final Logger logger = LoggerFactory.getLogger(ChatService.class);

	private static final String SYSTEM_PROMPT = """
			You are a helpful AI Agent for travel and expense management.
			Be friendly, helpful, and concise in your responses.

			IMPORTANT: Always call getCurrentDateTime first to know the current date before processing any request.

			Use the knowledge base context for internal company policies and procedures.
			Use searchWeb for current information from the internet.
			""";

	private final ChatClient chatClient;

	public ChatService(ChatClient.Builder chatClientBuilder,
			// Memory
			@Autowired(required = false) ChatMemoryRepository memoryRepository,
			@Autowired(required = false) List<Advisor> ltmAdvisors,
			// Knowledge Base
			@Autowired(required = false) VectorStore kbVectorStore,
			// Tools
			@Autowired(required = false) WebGroundingTools webGroundingTools) {

		// Memory
		List<Advisor> advisors = new ArrayList<>();
		if (memoryRepository != null) {
			ChatMemory chatMemory = MessageWindowChatMemory.builder().chatMemoryRepository(memoryRepository).build();
			advisors.add(MessageChatMemoryAdvisor.builder(chatMemory).order(10).build());
			logger.info("STM enabled");
		}
		if (ltmAdvisors != null && !ltmAdvisors.isEmpty()) {
			advisors.addAll(ltmAdvisors);
			logger.info("LTM enabled: {} advisors", ltmAdvisors.size());
		}

		// Knowledge Base
		if (kbVectorStore != null) {
			advisors.add(QuestionAnswerAdvisor.builder(kbVectorStore).order(1000).build());
			logger.info("KB RAG enabled");
		}

		// Tools
		List<Object> localTools = new ArrayList<>();

		localTools.add(new DateTimeTools());
		localTools.add(new WeatherTools());

		if (webGroundingTools != null) {
			localTools.add(webGroundingTools);
			logger.info("Web Grounding enabled");
		}

		// Build ChatClient
		this.chatClient = chatClientBuilder.defaultSystem(SYSTEM_PROMPT)
			.defaultAdvisors(advisors.toArray(new Advisor[0]))
			.defaultTools(localTools.toArray())
			.build();

		logger.info("ChatService initialized: {} advisors, {} local tools", advisors.size(), localTools.size());
	}

	public Flux<String> chat(InvocationRequest request, String sessionId) {
		return chat(request.prompt(), sessionId);
	}

	public Flux<String> chat(String prompt, String sessionId) {
		return chatClient.prompt()
			.user(prompt)
			.advisors(a -> a.param(ChatMemory.CONVERSATION_ID, sessionId))
			.stream()
			.content()
			.onErrorResume(e -> {
				logger.error("Chat error", e);
				return Flux.just("Error processing request.");
			});
	}

}
