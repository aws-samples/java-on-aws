package com.example.ai.agent.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatusCode;
import org.springframework.web.reactive.function.client.WebClient;
import org.testcontainers.containers.BindMode;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.Network;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.ollama.OllamaContainer;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.MountableFile;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Testcontainers
public class DeepEvalTest {

    private static final Network network = Network.newNetwork();

    @Container
    private static OllamaContainer ollamaContainer = new OllamaContainer("ollama/ollama:0.5.7")
            .withNetwork(network)
            .withNetworkAliases("ollama")
            .withReuse(true)
            .withFileSystemBind("/tmp/ollama-models-deepeval", "/root/.ollama", BindMode.READ_WRITE);

    @Container
    private static GenericContainer<?> deepEvalContainer = new GenericContainer<>(DockerImageName.parse("python:3.11-slim"))
            .withNetwork(network)
            .withCopyFileToContainer(
                MountableFile.forClasspathResource("deepeval-api.py"),
                "/app/deepeval-api.py"
            )
            .withCommand("sh", "-c", 
                "pip install flask deepeval requests && " +
                "python /app/deepeval-api.py"
            )
            .withExposedPorts(8080)
            .waitingFor(Wait.forHttp("/health").forPort(8080))
            .dependsOn(ollamaContainer);
    
    private static WebClient webClient;

    @Autowired
    private ChatService chatService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeAll
    static void setup() {
        deepEvalContainer.start();
        String baseUrl = "http://localhost:" + deepEvalContainer.getMappedPort(8080);
        webClient = WebClient.builder().baseUrl(baseUrl).build();
    }

    @Test
    public void testAnswerRelevancyWithDeepEval() {
        String question = "What documents do I need for car rental?";
        String response = chatService.processChat(question);
        
        System.out.println("=== DEEPEVAL RELEVANCY TEST ===");
        System.out.println("Question: " + question);
        System.out.println("Response: " + response);

        // Call DeepEval REST API
        var requestBody = objectMapper.createObjectNode()
            .put("input", question)
            .put("output", response)
            .put("threshold", 0.5);

        JsonNode result = webClient.post()
            .uri("/evaluate/relevancy")
            .bodyValue(requestBody)
            .retrieve()
            .onStatus(status -> status.is5xxServerError(), clientResponse -> {
                return clientResponse.bodyToMono(String.class)
                    .map(body -> new RuntimeException("Server error: " + body));
            })
            .bodyToMono(JsonNode.class)
            .block();
        
        System.out.println("=== DEEPEVAL RESULTS ===");
        System.out.println("Score: " + result.get("score").asDouble());
        System.out.println("Success: " + result.get("success").asBoolean());
        System.out.println("Reason: " + result.get("reason").asText());
        System.out.println("Metric: " + result.get("metric").asText());

        assertThat(result.get("success").asBoolean()).isTrue();
        assertThat(result.get("score").asDouble()).isGreaterThan(0.5);
    }

    @Test
    public void testFaithfulnessWithDeepEval() {
        String question = "What are hotel check-in requirements?";
        String context = "Hotel check-in requires valid ID and credit card. International guests need passport.";
        String response = "For hotel check-in, you need a valid ID and credit card. International travelers must present a passport.";
        
        System.out.println("=== DEEPEVAL FAITHFULNESS TEST ===");
        System.out.println("Question: " + question);
        System.out.println("Context: " + context);
        System.out.println("Response: " + response);

        // Call DeepEval REST API
        var requestBody = objectMapper.createObjectNode()
            .put("input", question)
            .put("output", response)
            .put("threshold", 0.5)
            .set("context", objectMapper.createArrayNode().add(context));

        JsonNode result = webClient.post()
            .uri("/evaluate/faithfulness")
            .bodyValue(requestBody)
            .retrieve()
            .onStatus(HttpStatusCode::is5xxServerError, clientResponse -> clientResponse.bodyToMono(String.class)
                .map(body -> new RuntimeException("Server error: " + body)))
            .bodyToMono(JsonNode.class)
            .block();
        
        System.out.println("=== DEEPEVAL RESULTS ===");
        System.out.println("Score: " + result.get("score").asDouble());
        System.out.println("Success: " + result.get("success").asBoolean());
        System.out.println("Reason: " + result.get("reason").asText());
        System.out.println("Metric: " + result.get("metric").asText());

        assertThat(result.get("success").asBoolean()).isTrue();
        assertThat(result.get("score").asDouble()).isGreaterThan(0.5);
    }
}