#!/bin/bash

# AI Agent Application - Create complete application with all features
# Based on: create + persona + memory + knowledge + tools + mcp-client + security modules
# Creates final state of all files ready for deployment or local run

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/aiagent

log_info "Creating AI Agent application..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"

# ============================================================================
# Generate project with Spring Initializr
# ============================================================================
log_info "Generating project with Spring Initializr..."
cd ~/environment/
curl -s https://start.spring.io/starter.zip \
  -d type=maven-project \
  -d language=java \
  -d packaging=jar \
  -d javaVersion=25 \
  -d bootVersion=3.5.9 \
  -d baseDir=aiagent \
  -d groupId=com.example \
  -d artifactId=agent \
  -d name=agent \
  -d description='AI Agent with Spring AI and Amazon Bedrock' \
  -d dependencies=spring-ai-bedrock-converse,web,webflux,actuator \
  -o aiagent.zip

unzip -q aiagent.zip
rm aiagent.zip
log_success "Project generated"

# ============================================================================
# application.properties - Final state with all configurations
# ============================================================================
log_info "Creating application.properties..."
cat <<'EOF' > ~/environment/aiagent/src/main/resources/application.properties
logging.level.org.springframework.ai=DEBUG

# Amazon Bedrock Configuration
spring.ai.bedrock.converse.chat.options.model=global.anthropic.claude-sonnet-4-20250514-v1:0
spring.ai.bedrock.converse.chat.options.max-tokens=4096

# JDBC Memory Configuration
spring.ai.chat.memory.repository.jdbc.initialize-schema=always

# RAG Configuration
spring.ai.model.embedding=bedrock-titan
spring.ai.bedrock.titan.embedding.model=amazon.titan-embed-text-v2:0
spring.ai.bedrock.titan.embedding.input-type=text
spring.ai.vectorstore.pgvector.initialize-schema=true
spring.ai.vectorstore.pgvector.dimensions=1024

# MCP Client Configuration
spring.ai.mcp.client.toolcallback.enabled=true

# Security Configuration
spring.security.oauth2.resourceserver.jwt.issuer-uri=${COGNITO_ISSUER_URI:}
EOF
log_success "application.properties created"

# ============================================================================
# pom.xml - Add all dependencies
# ============================================================================
log_info "Adding dependencies to pom.xml..."

# Add Security dependencies
sed -i '0,/<dependencies>/{/<dependencies>/a\
        <!-- Security dependencies -->\
        <dependency>\
            <groupId>org.springframework.boot</groupId>\
            <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>\
        </dependency>
}' ~/environment/aiagent/pom.xml

# Add MCP Client dependencies
sed -i '0,/<dependencies>/{/<dependencies>/a\
        <!-- MCP Client dependencies -->\
        <dependency>\
            <groupId>org.springframework.ai</groupId>\
            <artifactId>spring-ai-starter-mcp-client</artifactId>\
        </dependency>
}' ~/environment/aiagent/pom.xml

# Add RAG Dependencies
sed -i '0,/<dependencies>/{/<dependencies>/a\
        <!-- RAG Dependencies -->\
        <dependency>\
            <groupId>org.springframework.ai</groupId>\
            <artifactId>spring-ai-advisors-vector-store</artifactId>\
        </dependency>\
        <dependency>\
            <groupId>org.springframework.ai</groupId>\
            <artifactId>spring-ai-starter-vector-store-pgvector</artifactId>\
        </dependency>\
        <dependency>\
            <groupId>org.springframework.ai</groupId>\
            <artifactId>spring-ai-starter-model-bedrock</artifactId>\
        </dependency>
}' ~/environment/aiagent/pom.xml

# Add JDBC Memory dependencies
sed -i '0,/<dependencies>/{/<dependencies>/a\
        <!-- JDBC Memory dependencies -->\
        <dependency>\
            <groupId>org.springframework.ai</groupId>\
            <artifactId>spring-ai-starter-model-chat-memory-repository-jdbc</artifactId>\
        </dependency>\
        <dependency>\
            <groupId>org.postgresql</groupId>\
            <artifactId>postgresql</artifactId>\
            <scope>runtime</scope>\
        </dependency>
}' ~/environment/aiagent/pom.xml

log_success "Dependencies added"

# ============================================================================
# Java source files - Final state
# ============================================================================
log_info "Creating Java source files..."

# InvocationRequest.java
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/InvocationRequest.java
package com.example.agent;

public record InvocationRequest(String prompt) {}
EOF

# DateTimeTools.java
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/DateTimeTools.java
package com.example.agent;

import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

class DateTimeTools {

    @Tool(description = """
        Get the current date and time in a specific time zone.
        Use for answering questions requiring date time knowledge,
        like today, tomorrow, next week, next month.
        """)
    public String getCurrentDateTime(
            @ToolParam(description = "Time zone ID, e.g. Europe/Paris, America/New_York, UTC")
            String timeZone) {
        return ZonedDateTime.now(ZoneId.of(timeZone))
            .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }
}
EOF

# WeatherTools.java
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/WeatherTools.java
package com.example.agent;

import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.web.client.RestClient;

class WeatherTools {

    private static final Logger log = LoggerFactory.getLogger(WeatherTools.class);
    private static final ParameterizedTypeReference<Map<String, Object>> MAP_TYPE =
        new ParameterizedTypeReference<>() {};
    private final RestClient restClient = RestClient.create();

    @Tool(description = """
        Get weather forecast for a city on a specific date.
        Use for answering questions about weather forecasts.
        """)
    public String getWeather(
            @ToolParam(description = "City name, e.g. Paris, London, New York") String city,
            @ToolParam(description = "Date in YYYY-MM-DD format, e.g. 2025-01-27") String date) {
        log.info("getWeather called with city={}, date={}", city, date);
        try {
            var geo = restClient.get()
                .uri("https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1", city)
                .retrieve().body(MAP_TYPE);

            var results = (List<Map<String, Object>>) geo.get("results");
            if (results == null || results.isEmpty()) return "City not found: " + city;

            var loc = results.get(0);
            var weather = restClient.get()
                .uri("https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}" +
                     "&daily=temperature_2m_max,temperature_2m_min&timezone=auto" +
                     "&start_date={startDate}&end_date={endDate}",
                     loc.get("latitude"), loc.get("longitude"), date, date)
                .retrieve().body(MAP_TYPE);

            if (weather.containsKey("error")) {
                var error = "Weather API error: " + weather.get("reason");
                log.warn(error);
                return error;
            }

            var daily = (Map<String, List<Number>>) weather.get("daily");
            var units = (Map<String, String>) weather.get("daily_units");

            var result = "Weather for %s on %s: Min: %.1f%s, Max: %.1f%s".formatted(
                loc.get("name"), date,
                daily.get("temperature_2m_min").get(0).doubleValue(), units.get("temperature_2m_min"),
                daily.get("temperature_2m_max").get(0).doubleValue(), units.get("temperature_2m_max"));
            log.info("getWeather result: {}", result);
            return result;
        } catch (Exception e) {
            log.error("getWeather error", e);
            return "Error fetching weather: " + e.getMessage();
        }
    }
}
EOF

# SecurityConfig.java
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/SecurityConfig.java
package com.example.agent;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri:}")
    private String issuerUri;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.disable());
        http.authorizeHttpRequests(auth -> auth
            .requestMatchers("/", "/*.js", "/*.css", "/*.json", "/*.svg", "/*.html").permitAll()
            .requestMatchers("/actuator/**").permitAll()
        );

        if (issuerUri != null && !issuerUri.isBlank()) {
            http.authorizeHttpRequests(auth -> auth
                    .requestMatchers("/invocations").authenticated()
                    .anyRequest().permitAll())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        } else {
            http.authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        }

        return http.build();
    }
}
EOF

# ChatService.java - Final state with all features
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/ChatService.java
package com.example.agent;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import javax.sql.DataSource;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import java.util.List;
import org.springframework.ai.tool.ToolCallbackProvider;

@Service
public class ChatService {

    private static final String DEFAULT_SYSTEM_PROMPT = """
        You are a helpful AI assistant for Unicorn Rentals, a fictional company that rents unicorns.
        Be friendly, helpful, and concise in your responses.
        If you don't have information, say I don't know, don't think up.
        """;

    private final ChatClient chatClient;
    private final VectorStore vectorStore;

    public ChatService(ChatClient.Builder chatClientBuilder, DataSource dataSource, VectorStore vectorStore, ToolCallbackProvider tools) {

        this.vectorStore = vectorStore;

        var chatMemoryRepository = JdbcChatMemoryRepository.builder()
            .dataSource(dataSource)
            .dialect(new PostgresChatMemoryRepositoryDialect())
            .build();

        var chatMemory = MessageWindowChatMemory.builder()
            .chatMemoryRepository(chatMemoryRepository)
            .maxMessages(20)
            .build();

        this.chatClient = chatClientBuilder
            .defaultSystem(DEFAULT_SYSTEM_PROMPT)
            .defaultAdvisors(
                MessageChatMemoryAdvisor.builder(chatMemory).build(),
                QuestionAnswerAdvisor.builder(vectorStore).build()
            )
            .defaultTools(new DateTimeTools(), new WeatherTools())
            .defaultToolCallbacks(tools)
            .build();
    }

    public Flux<String> chat(String prompt, String username) {
        return chatClient.prompt().user(prompt)
            .advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, username))
            .stream().content();
    }

    public void loadDocument(String content) {
        vectorStore.add(List.of(new Document(content)));
    }
}
EOF

# InvocationController.java - Final state with security and /load endpoint
cat <<'EOF' > ~/environment/aiagent/src/main/java/com/example/agent/InvocationController.java
package com.example.agent;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

@RestController
@CrossOrigin(origins = "*")
@ConditionalOnProperty(name = "app.controller.enabled", havingValue = "true", matchIfMissing = true)
public class InvocationController {
    private final ChatService chatService;

    public InvocationController(ChatService chatService) {
        this.chatService = chatService;
    }

    @PostMapping(value = "invocations", produces = MediaType.TEXT_PLAIN_VALUE)
    public Flux<String> handleInvocation(
            @RequestBody InvocationRequest request,
            @AuthenticationPrincipal Jwt jwt) {
        if (jwt == null) {
            return chatService.chat(request.prompt(), "default");
        }
        String visitorId = jwt.getSubject().replace("-", "").substring(0, 25);
        String sessionId = jwt.getClaim("auth_time").toString();
        return chatService.chat(request.prompt(), visitorId + ":" + sessionId);
    }

    @PostMapping(value = "load", consumes = MediaType.TEXT_PLAIN_VALUE)
    public void loadDocument(@RequestBody String content) {
        chatService.loadDocument(content);
    }
}
EOF

log_success "Java source files created"

# ============================================================================
# Static files and config
# ============================================================================
log_info "Copying static files..."
cp ~/java-on-aws/apps/aiagent/src/main/resources/static/* \
  ~/environment/aiagent/src/main/resources/static/

# Create Cognito config.json (if Cognito exists)
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text 2>/dev/null || echo "")

if [[ -n "${USER_POOL_ID}" && "${USER_POOL_ID}" != "None" ]]; then
    CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "${USER_POOL_ID}" --no-cli-pager \
      --query "UserPoolClients[?ClientName=='aiagent-client'].ClientId | [0]" --output text)

    cat > ~/environment/aiagent/src/main/resources/static/config.json << EOF
{
  "userPoolId": "${USER_POOL_ID}",
  "clientId": "${CLIENT_ID}",
  "apiEndpoint": "invocations"
}
EOF
    log_success "Cognito config.json created"
else
    log_info "Cognito not configured, skipping config.json"
fi

# ============================================================================
# Initialize Git repository
# ============================================================================
log_info "Initializing Git repository..."
cd ~/environment/aiagent
git config --global user.email "workshop-user@example.com"
git config --global user.name "workshop-user"
git init -b main
git add .
git commit -q -m "Create AI Agent with all features"
log_success "Git repository initialized"

log_success "AI Agent application created"
echo "✅ Success: AI Agent ready at ~/environment/aiagent"
