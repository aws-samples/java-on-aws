package com.unicorn.agents;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

@RestController
public class ChatController {

	private final ChatClient chatClient;

	public ChatController (ChatClient.Builder chatClient){
		this.chatClient = chatClient
				.defaultTools(new DateTimeTools())
				.build();
	}

	@PostMapping("/ai")
	public String myAgent(@RequestBody PromptRequest promptRequest){
		return chatClient.prompt().user(promptRequest.prompt()).call().chatResponse().toString();
	}

	@PostMapping("/ai/stream")
	public Flux<String> myStreamingAgent(@RequestBody PromptRequest promptRequest){
		return chatClient.prompt().user(promptRequest.prompt()).stream().content();
	}


}
