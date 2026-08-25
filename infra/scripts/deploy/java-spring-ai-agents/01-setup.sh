#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then FORCE=true; shift; fi
(($# == 0)) || die "Usage: 01-setup.sh [--force]"
print_prerequisites "rsync and the checked-out java-on-aws seed applications"
init_context
require_cmd rsync

AI_SEED="${REPO_ROOT}/apps/aiagent"
MCP_SEED="${REPO_ROOT}/apps/unicorn-store-spring"
[[ -d "${AI_SEED}" ]] || die "AI-agent seed not found: ${AI_SEED}"
[[ -d "${MCP_SEED}" ]] || die "MCP seed not found: ${MCP_SEED}"

prepare_destination() {
  local destination="$1" label="$2"
  if [[ -d "${destination}" && "${FORCE}" != true ]]; then
    log "Preserving existing ${label}: ${destination} (use --force to refresh suite-managed files)"
    return 1
  fi
  mkdir -p "${destination}"
  return 0
}

if prepare_destination "${AIAGENT_DIR}" "AI-agent directory"; then
  if [[ "${FORCE}" == true ]]; then rm -rf "${AIAGENT_DIR}/src/test"; fi
  rsync -a --delete "${AI_SEED}/" "${AIAGENT_DIR}/" --exclude .git --exclude target --exclude src/test
  mkdir -p "${AIAGENT_DIR}/src/main/java/com/example/agent" "${AIAGENT_DIR}/src/main/resources/static"

  cat > "${AIAGENT_DIR}/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>4.1.0</version><relativePath/></parent>
  <groupId>com.example</groupId><artifactId>agent</artifactId><version>0.0.1-SNAPSHOT</version>
  <name>agent</name><description>Unicorn Rentals AI Agent with Spring AI and Amazon Bedrock</description>
  <properties><java.version>25</java.version><spring-ai.version>2.0.1</spring-ai.version></properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-webflux</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-oauth2-resource-server</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-starter-model-bedrock-converse</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-starter-model-bedrock</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-starter-model-chat-memory-repository-jdbc</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-vector-store-advisor</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-starter-vector-store-pgvector</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-starter-mcp-client</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
  </dependencies>
  <dependencyManagement><dependencies><dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-bom</artifactId><version>${spring-ai.version}</version><type>pom</type><scope>import</scope></dependency></dependencies></dependencyManagement>
  <build><plugins>
    <plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin>
    <plugin><groupId>com.google.cloud.tools</groupId><artifactId>jib-maven-plugin</artifactId><version>3.5.1</version><configuration><from><image>public.ecr.aws/docker/library/amazoncorretto:25-alpine</image></from><container><user>1000</user></container></configuration></plugin>
  </plugins></build>
</project>
EOF

  cat > "${AIAGENT_DIR}/src/main/resources/application.properties" <<'EOF'
logging.level.org.springframework.ai=DEBUG
# Modern Spring AI 2.0 Bedrock Converse properties.
spring.ai.bedrock.aws.timeout=120s
spring.ai.bedrock.converse.chat.model=global.anthropic.claude-sonnet-4-6
spring.ai.bedrock.converse.chat.max-tokens=4096
spring.ai.bedrock.converse.chat.temperature=0.7
spring.ai.chat.memory.repository.jdbc.initialize-schema=always
spring.ai.model.embedding=bedrock-titan
spring.ai.bedrock.titan.embedding.model=amazon.titan-embed-text-v2:0
spring.ai.bedrock.titan.embedding.input-type=text
spring.ai.vectorstore.pgvector.initialize-schema=true
spring.ai.vectorstore.pgvector.dimensions=1024
spring.ai.mcp.client.toolcallback.enabled=true
spring.security.oauth2.resourceserver.jwt.issuer-uri=${COGNITO_ISSUER_URI:}
EOF

  cat > "${AIAGENT_DIR}/src/main/java/com/example/agent/InvocationRequest.java" <<'EOF'
package com.example.agent;
public record InvocationRequest(String prompt, String verificationDocument) {}
EOF
  cat > "${AIAGENT_DIR}/src/main/java/com/example/agent/DateTimeTools.java" <<'EOF'
package com.example.agent;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
class DateTimeTools {
    @Tool(description = "Get the current date and time in a specific time zone. Use for questions requiring current date knowledge.")
    public String getCurrentDateTime(@ToolParam(description = "Time zone ID, for example Europe/Paris, America/New_York, or UTC") String timeZone) {
        return ZonedDateTime.now(ZoneId.of(timeZone)).format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }
}
EOF
  cat > "${AIAGENT_DIR}/src/main/java/com/example/agent/WeatherTools.java" <<'EOF'
package com.example.agent;
import java.net.http.HttpClient;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;
class WeatherTools {
    private static final Logger log = LoggerFactory.getLogger(WeatherTools.class);
    private static final ParameterizedTypeReference<Map<String, Object>> MAP_TYPE = new ParameterizedTypeReference<>() {};
    private final RestClient restClient = RestClient.builder().requestFactory(new JdkClientHttpRequestFactory(HttpClient.newHttpClient())).build();
    @Tool(description = "Get the weather forecast for a city on a specific date.")
    @SuppressWarnings("unchecked")
    public String getWeather(@ToolParam(description = "City name") String city, @ToolParam(description = "Date in YYYY-MM-DD format") String date) {
        log.info("getWeather called with city={}, date={}", city, date);
        try {
            var geo = restClient.get().uri("https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1", city).retrieve().body(MAP_TYPE);
            var results = (List<Map<String, Object>>) geo.get("results");
            if (results == null || results.isEmpty()) return "City not found: " + city;
            var loc = results.get(0);
            var weather = restClient.get().uri("https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date={startDate}&end_date={endDate}", loc.get("latitude"), loc.get("longitude"), date, date).retrieve().body(MAP_TYPE);
            if (weather.containsKey("error")) return "Weather API error: " + weather.get("reason");
            var daily = (Map<String, List<Number>>) weather.get("daily");
            var units = (Map<String, String>) weather.get("daily_units");
            return "Weather for %s on %s: Min: %.1f%s, Max: %.1f%s".formatted(loc.get("name"), date, daily.get("temperature_2m_min").get(0).doubleValue(), units.get("temperature_2m_min"), daily.get("temperature_2m_max").get(0).doubleValue(), units.get("temperature_2m_max"));
        } catch (Exception e) {
            log.error("getWeather error", e);
            return "Error fetching weather: " + e.getMessage();
        }
    }
}
EOF
  cat > "${AIAGENT_DIR}/src/main/java/com/example/agent/ChatService.java" <<'EOF'
package com.example.agent;
import java.util.List;
import javax.sql.DataSource;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.chat.memory.repository.jdbc.PostgresChatMemoryRepositoryDialect;
import org.springframework.ai.document.Document;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
@Service
public class ChatService {
    private static final String DEFAULT_SYSTEM_PROMPT = """
        You are a helpful AI assistant for Unicorn Rentals, a fictional company that rents unicorns.
        Be friendly, helpful, and concise in your responses.
        If you don't have information, say I don't know; do not invent it.
        """;
    private final ChatClient chatClient;
    private final VectorStore vectorStore;
    public ChatService(ChatClient.Builder builder, DataSource dataSource, VectorStore vectorStore, ToolCallbackProvider tools) {
        this.vectorStore = vectorStore;
        var repository = JdbcChatMemoryRepository.builder().dataSource(dataSource).dialect(new PostgresChatMemoryRepositoryDialect()).build();
        var memory = MessageWindowChatMemory.builder().chatMemoryRepository(repository).maxMessages(20).build();
        this.chatClient = builder.defaultSystem(DEFAULT_SYSTEM_PROMPT)
            .defaultAdvisors(MessageChatMemoryAdvisor.builder(memory).build(), QuestionAnswerAdvisor.builder(vectorStore).build())
            .defaultTools(new DateTimeTools(), new WeatherTools()).defaultToolCallbacks(tools).build();
    }
    public Flux<String> chat(String prompt, String username) {
        return chatClient.prompt().user(prompt).advisors(a -> a.param(ChatMemory.CONVERSATION_ID, username)).stream().content();
    }
    public void loadDocument(String content) { vectorStore.add(List.of(new Document(content))); }
}
EOF
  cat > "${AIAGENT_DIR}/src/main/java/com/example/agent/InvocationController.java" <<'EOF'
package com.example.agent;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Flux;
@RestController
@CrossOrigin(origins = "*")
public class InvocationController {
    private static final int MAX_VERIFICATION_DOCUMENT_LENGTH = 4096;
    private final ChatService chatService;
    public InvocationController(ChatService chatService) { this.chatService = chatService; }
    @PostMapping(value = "invocations", produces = MediaType.TEXT_PLAIN_VALUE)
    public Flux<String> handleInvocation(@RequestBody InvocationRequest request, @AuthenticationPrincipal Jwt jwt) {
        if (request.verificationDocument() != null) {
            requireAdmin(jwt);
            loadVerificationDocument(request.verificationDocument());
            return Flux.just("Knowledge loaded");
        }
        if (jwt == null) return chatService.chat(request.prompt(), "default");
        String visitorId = jwt.getSubject().replace("-", "").substring(0, 25);
        return chatService.chat(request.prompt(), visitorId + ":" + jwt.getClaim("auth_time"));
    }
    @PostMapping(value = "load", consumes = MediaType.TEXT_PLAIN_VALUE)
    public void loadDocument(@RequestBody String content, @AuthenticationPrincipal Jwt jwt) {
        requireAdmin(jwt);
        loadVerificationDocument(content);
    }
    private void requireAdmin(Jwt jwt) {
        String username = jwt == null ? null : jwt.getClaimAsString("cognito:username");
        if (username == null && jwt != null) username = jwt.getClaimAsString("username");
        if (!"admin".equals(username)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
    }
    private void loadVerificationDocument(String content) {
        if (content.isBlank() || content.length() > MAX_VERIFICATION_DOCUMENT_LENGTH) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Knowledge document must contain 1-4096 characters");
        }
        chatService.loadDocument(content);
    }
}
EOF
  cat > "${AIAGENT_DIR}/src/main/java/com/example/agent/SecurityConfig.java" <<'EOF'
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
    @Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri:}") private String issuerUri;
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.disable());
        http.authorizeHttpRequests(auth -> auth.requestMatchers("/", "/*.js", "/*.css", "/*.json", "/*.svg", "/*.html", "/actuator/**").permitAll());
        if (issuerUri != null && !issuerUri.isBlank()) {
            http.authorizeHttpRequests(auth -> auth.requestMatchers("/invocations", "/load").authenticated().anyRequest().permitAll())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        } else {
            http.authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        }
        return http.build();
    }
}
EOF
  state_set AIAGENT_SOURCE_READY true
  log "Materialized complete AI-agent source at ${AIAGENT_DIR}"
fi

if prepare_destination "${MCPSERVER_DIR}" "MCP-server directory"; then
  if [[ "${FORCE}" == true ]]; then rm -rf "${MCPSERVER_DIR}/src/test"; fi
  rsync -a --delete "${MCP_SEED}/" "${MCPSERVER_DIR}/" --exclude .git --exclude target --exclude src/test
  require_cmd python3
  python3 - "${MCPSERVER_DIR}/pom.xml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if "spring-ai-bom" not in s:
    marker = "    <dependencyManagement>\n        <dependencies>\n"
    bom = """            <dependency>\n                <groupId>org.springframework.ai</groupId>\n                <artifactId>spring-ai-bom</artifactId>\n                <version>2.0.1</version>\n                <type>pom</type>\n                <scope>import</scope>\n            </dependency>\n"""
    s = s.replace(marker, marker + bom, 1)
if "spring-ai-starter-mcp-server-webmvc" not in s:
    marker = "        <!-- Spring Boot starters -->"
    dep = """        <dependency>\n            <groupId>org.springframework.ai</groupId>\n            <artifactId>spring-ai-starter-mcp-server-webmvc</artifactId>\n        </dependency>\n\n"""
    s = s.replace(marker, dep + marker, 1)
p.write_text(s)
PY
  cat > "${MCPSERVER_DIR}/src/main/resources/application.properties" <<'EOF'
spring.ai.mcp.server.name=unicorn-store-spring
spring.ai.mcp.server.version=1.0.0
spring.ai.mcp.server.protocol=STREAMABLE
logging.level.org.springframework.ai=DEBUG
EOF
  cat > "${MCPSERVER_DIR}/src/main/java/com/unicorn/store/service/UnicornTools.java" <<'EOF'
package com.unicorn.store.service;
import com.unicorn.store.model.Unicorn;
import java.util.List;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;
@Component
public class UnicornTools {
    private final UnicornService unicornService;
    public UnicornTools(UnicornService unicornService) { this.unicornService = unicornService; }
    @Bean
    public ToolCallbackProvider unicornToolsProvider(UnicornTools tools) {
        return MethodToolCallbackProvider.builder().toolObjects(tools).build();
    }
    @Tool(description = "Create a new unicorn in the unicorn store.")
    public Unicorn createUnicorn(Unicorn unicorn) { return unicornService.createUnicorn(unicorn); }
    @Tool(description = "Get a list of all unicorns in the unicorn store")
    public List<Unicorn> getAllUnicorns(String... parameters) { return unicornService.getAllUnicorns(); }
}
EOF
  state_set MCPSERVER_SOURCE_READY true
  log "Materialized complete MCP-server source at ${MCPSERVER_DIR}"
fi

log "Setup complete. No Git repository was initialized and no commit was created."
