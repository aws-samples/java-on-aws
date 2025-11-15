package com.example.ai.agent.controller;

import com.example.ai.agent.service.ChatService;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("api")
public class ChatController {

    private final ChatService chatService;

    public ChatController(ChatService chatService) {
        this.chatService = chatService;
    }

	@PostMapping("chat")
    public String chat(@RequestBody ChatRequest request) {
		return chatService.processChat(request.prompt());
    }

    @GetMapping("gui")
    public String chat() {
        String prompt = "Please give me all available hotels in Paris, Checkin 10.10.2025, checkout 15.10.2025";
        String chatResponse = chatService.processChat(prompt);

        String currentHotel = """
					<h2>Available hotels %s</h2>
					<p>%s</p>
					<form action="" method="GET">
					<button type="submit">Clear</button>
					</form>
					""".formatted(prompt, chatResponse);

        return """
				<h1>Demo controller</h1>
				%s

				<hr>

				<h2>Ask for the weather</h2>
				<p>In which city would you like to see the weather?</p>
				<form action="" method="GET">
				    <input type="text" name="query" value="" placeholder="Paris" />
				    <button type="submit">Ask the LLM</button>
				</form>

				<hr>
				""".formatted(currentHotel);
    }


    public record ChatRequest(String prompt) {}
}
