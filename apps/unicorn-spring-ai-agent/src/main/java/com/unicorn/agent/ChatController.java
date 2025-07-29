package com.unicorn.agent;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.ChatMemoryRepository;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.ai.document.Document;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import javax.sql.DataSource;
import java.util.List;
import reactor.core.publisher.Flux;

@RestController
@RequestMapping("api")
public class ChatController {

    private static final String DEFAULT_SYSTEM_PROMPT = """
		You are a helpful AI assistant for Unicorn Rentals, a fictional company that rents unicorns.
		Be friendly, helpful, and concise in your responses.
		""";

	private final ChatClient chatClient;
	private final VectorStore vectorStore;

	public ChatController (ChatClient.Builder chatClient, DataSource dataSource, VectorStore vectorStore){
		var chatMemoryRepository = JdbcChatMemoryRepository.builder()
			.dataSource(dataSource)
			.dialect(new PostgresChatMemoryRepositoryDialect())
			.build();

		var chatMemory = MessageWindowChatMemory.builder()
			.chatMemoryRepository(chatMemoryRepository)
			.maxMessages(20)
			.build();

		this.vectorStore = vectorStore;

		this.chatClient = chatClient
			.defaultSystem(DEFAULT_SYSTEM_PROMPT)
			.defaultAdvisors(
				MessageChatMemoryAdvisor.builder(chatMemory).build(),
				QuestionAnswerAdvisor.builder(vectorStore).build())
            .defaultTools(new DateTimeTools(), new WeatherTools())
			.build();
	}

	@PostMapping("load")
    public void loadDataToVectorStore(@RequestBody String content) {
        vectorStore.add(List.of(new Document(content)));
    }

	@PostMapping("/chat/stream")
	public Flux<String> chatStream(@RequestBody PromptRequest promptRequest){
		var conversationId = "user1"; //This should be retrieved from the Auth context
		return chatClient.prompt().user(promptRequest.prompt())
			.advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, conversationId))
			.stream().content();
	}

    record PromptRequest(String prompt) {
    }

}