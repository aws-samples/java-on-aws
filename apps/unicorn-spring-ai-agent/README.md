# Unicorn Spring AI Agent

A comprehensive AI-powered assistant built with Spring AI framework for Unicorn Rentals, featuring chat capabilities, persistent memory, RAG (Retrieval-Augmented Generation), tool integration, and observability.

The is the application for the [Building Java AI Agents with Spring AI](https://catalog.workshops.aws/java-spring-ai-agents/en-US) workshop.

## Project Overview

### Description

The Unicorn Spring AI Agent is a demonstration of how to build modern AI-powered applications using the Spring AI framework. It provides a complete set of capabilities for interacting with AI models, including:

- Text-based conversations with persistent memory using PostgreSQL
- Retrieval-Augmented Generation (RAG) for knowledge base integration using pgvector
- Tool integration for enhanced capabilities (DateTime and Weather tools)
- Real-time streaming chat interface
- Comprehensive observability with metrics, logs, and traces
- Modern web interface built with Thymeleaf and Tailwind CSS

The application serves as a practical example of building AI assistants with Spring Boot and demonstrates key AI application patterns.

### Purpose

This application serves as:

1. A reference implementation for Spring AI integration in enterprise applications
2. A demonstration of key AI application patterns (RAG, memory, tools, observability)
3. A practical example of building AI assistants with Spring Boot
4. A showcase for integrating with Amazon Bedrock and other AWS services

### Technology Stack

- **Java 21**: Latest LTS version with modern language features
- **Spring Boot 3.5.4**: Core framework for building the application
- **Spring AI 1.0.0**: AI integration framework
- **Amazon Bedrock**: AI model provider (Claude 3.7 Sonnet)
- **PostgreSQL**: Database with pgvector extension for vector operations
- **Thymeleaf**: Server-side templating for the web interface
- **Tailwind CSS**: Utility-first CSS framework for styling
- **Micrometer**: Metrics collection and observability


## Architecture

### Component Architecture

The application follows a layered architecture with the following components:

```
┌─────────────────────────────────────────────────────────────┐
│                    Web Interface (Thymeleaf)                │
├─────────────────────────────────────────────────────────────┤
│                    REST API Layer                           │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  ChatController │  │  WebController  │                  │
│  └─────────────────┘  └─────────────────┘                  │
├─────────────────────────────────────────────────────────────┤
│                    Spring AI Layer                          │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │   ChatClient    │  │   Advisors      │                  │
│  │                 │  │  - Memory       │                  │
│  │                 │  │  - RAG          │                  │
│  └─────────────────┘  └─────────────────┘                  │
├─────────────────────────────────────────────────────────────┤
│                    Tools Layer                              │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  DateTimeTools  │  │  WeatherTools   │                  │
│  └─────────────────┘  └─────────────────┘                  │
├─────────────────────────────────────────────────────────────┤
│                    Data Layer                               │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │   PostgreSQL    │  │   Vector Store  │                  │
│  │  (Chat Memory)  │  │   (pgvector)    │                  │
│  └─────────────────┘  └─────────────────┘                  │
├─────────────────────────────────────────────────────────────┤
│                    External Services                        │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │ Amazon Bedrock  │  │  Open-Meteo API │                  │
│  │ (Claude Sonnet) │  │   (Weather)     │                  │
│  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

1. **ChatController**: REST API endpoint for chat interactions and vector store management
2. **WebController**: Serves the web interface
3. **DateTimeTools**: Provides current date/time functionality
4. **WeatherTools**: Integrates with Open-Meteo API for weather forecasts
5. **Chat Memory**: Persistent conversation history using PostgreSQL
6. **Vector Store**: RAG implementation using pgvector for document retrieval

## Getting Started

### Prerequisites

- Java 21 or higher
- Maven 3.8 or higher
- Docker and Docker Compose (for PostgreSQL)
- PostgreSQL with pgvector extension
- AWS account with Amazon Bedrock access

### Database Setup

The application requires a PostgreSQL database with the pgvector extension for both chat memory and vector storage.

#### Using Docker (Recommended)

```bash
# Start PostgreSQL with pgvector extension
docker run --name postgres-ai \
  -e POSTGRES_DB=unicorn_agent \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  -d pgvector/pgvector:pg16
```

#### Manual Setup

If you have PostgreSQL installed locally:

```sql
-- Create database
CREATE DATABASE unicorn_agent;

-- Connect to the database and enable pgvector extension
\c unicorn_agent;
CREATE EXTENSION IF NOT EXISTS vector;
```

### AWS Configuration

1. Configure AWS credentials:
   ```bash
   aws configure
   ```

2. Ensure you have access to Amazon Bedrock and the required models:
   - Claude 3.7 Sonnet (`us.anthropic.claude-3-7-sonnet-20250219-v1:0`)
   - Titan Embed Text v2 (`amazon.titan-embed-text-v2:0`)

### Application Configuration

Update the `application.properties` file with your database connection details:

```properties
# Database Configuration
spring.datasource.url=jdbc:postgresql://localhost:5432/unicorn_agent
spring.datasource.username=postgres
spring.datasource.password=postgres

# AWS Region (adjust as needed)
spring.ai.bedrock.aws.region=us-east-1
```

### Building and Running the Application

1. Clone and navigate to the project:
   ```bash
   cd /path/to/unicorn-spring-ai-agent
   ```

2. Build the application:
   ```bash
   mvn clean package
   ```

3. Run the application:
   ```bash
   mvn spring-boot:run
   ```

4. The application will be available at:
   ```
   http://localhost:8080
   ```

## Key Spring AI Features

This project demonstrates key features of the [Spring AI framework](https://docs.spring.io/spring-ai/reference/index.html).

### System Prompt Configuration

The AI assistant's behavior is defined through a system prompt configured in the `ChatController`:

```java
private static final String DEFAULT_SYSTEM_PROMPT = """
    You are a helpful AI assistant for Unicorn Rentals, a fictional company that rents unicorns.
    Be friendly, helpful, and concise in your responses.
    """;
```

### Chat Memory Integration

Spring AI provides built-in support for [persistent chat memory](https://docs.spring.io/spring-ai/reference/api/clients/chat-memory.html), allowing the assistant to remember conversation history:

```java
var chatMemoryRepository = JdbcChatMemoryRepository.builder()
    .dataSource(dataSource)
    .dialect(new PostgresChatMemoryRepositoryDialect())
    .build();

var chatMemory = MessageWindowChatMemory.builder()
    .chatMemoryRepository(chatMemoryRepository)
    .maxMessages(20)
    .build();
```

The memory is integrated with the ChatClient using the MessageChatMemoryAdvisor:

```java
this.chatClient = chatClient
    .defaultSystem(DEFAULT_SYSTEM_PROMPT)
    .defaultAdvisors(
        MessageChatMemoryAdvisor.builder(chatMemory).build(),
        // other advisors
    )
    .build();
```

### RAG (Retrieval-Augmented Generation)

Spring AI provides built-in support for [RAG](https://docs.spring.io/spring-ai/reference/api/vectordbs.html), allowing the assistant to retrieve relevant information from a vector database:

```java
this.chatClient = chatClient
    .defaultAdvisors(
        MessageChatMemoryAdvisor.builder(chatMemory).build(),
        QuestionAnswerAdvisor.builder(vectorStore).build()
    )
    .build();
```

Documents can be added to the vector store via the REST API:

```java
@PostMapping("load")
public void loadDataToVectorStore(@RequestBody String content) {
    vectorStore.add(List.of(new Document(content)));
}
```

### Tool Integration

Spring AI supports [tool integration](https://docs.spring.io/spring-ai/reference/api/clients/tools.html), allowing the assistant to call external functions.

#### DateTime Tool

```java
@Tool(description = "Get the current date and time")
public String getCurrentDateTime(String timeZone) {
    return java.time.ZonedDateTime.now(java.time.ZoneId.of(timeZone))
            .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
}
```

#### Weather Tool

```java
@Tool(description = "Get weather forecast for a city on a specific date (format: YYYY-MM-DD)")
public String getWeather(String city, String date) {
    // Implementation using Open-Meteo API
    // Returns weather forecast for the specified city and date
}
```

Tools are integrated with the ChatClient:

```java
this.chatClient = chatClient
    .defaultTools(new DateTimeTools(), new WeatherTools())
    .build();
```

### Streaming Responses

The application supports real-time streaming responses:

```java
@PostMapping("/chat/stream")
public Flux<String> chatStream(@RequestBody PromptRequest promptRequest){
    var conversationId = "user1";
    return chatClient.prompt().user(promptRequest.prompt())
        .advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, conversationId))
        .stream().content();
}
```

## API Endpoints

### Chat API

- **POST** `/api/chat/stream` - Stream chat responses
  ```json
  {
    "prompt": "What's the weather like in New York tomorrow?"
  }
  ```

### Vector Store API

- **POST** `/api/load` - Add content to the vector store
  ```
  Content-Type: text/plain
  Body: "Your document content here"
  ```

### Web Interface

- **GET** `/` - Main chat interface

## Web Interface

The application provides a modern web interface built with Thymeleaf and Tailwind CSS, featuring:

1. **Real-time Chat**: Streaming responses with typing indicators
2. **Dark Mode Design**: Professional developer-friendly interface
3. **Responsive Layout**: Works on desktop and mobile devices
4. **Message History**: Persistent conversation history
5. **Loading States**: Visual feedback during AI processing

### Key Features

- Real-time streaming responses
- Conversation memory across sessions
- Tool integration (weather, datetime)
- Document loading for RAG
- Professional dark theme

## Configuration

### Application Properties

```properties
# Application Configuration
spring.application.name=agent
logging.level.org.springframework.ai=DEBUG

# Amazon Bedrock Configuration
spring.ai.bedrock.converse.chat.options.model=us.anthropic.claude-3-7-sonnet-20250219-v1:0

# UI Configuration
spring.thymeleaf.cache=false
spring.thymeleaf.prefix=classpath:/templates/
spring.thymeleaf.suffix=.html

# Database Configuration
spring.datasource.username=postgres
# Note: spring.datasource.url and spring.datasource.password should be set via environment variables

# JDBC Memory Configuration
spring.ai.chat.memory.repository.jdbc.initialize-schema=always

# RAG Configuration
spring.ai.model.embedding=bedrock-titan
spring.ai.bedrock.titan.embedding.model=amazon.titan-embed-text-v2:0
spring.ai.bedrock.titan.embedding.input-type=text
spring.ai.vectorstore.pgvector.initialize-schema=true
spring.ai.vectorstore.pgvector.dimensions=1024

# Observability Configuration
## Logs
spring.ai.chat.client.observations.log-prompt=true
spring.ai.chat.observations.log-prompt=true
spring.ai.chat.observations.log-completion=true
spring.ai.chat.observations.include-error-logging=true
spring.ai.tools.observations.include-content=true
spring.ai.vectorstore.observations.log-query-response=true

## Metrics
management.endpoints.web.exposure.include=health, info, metrics, prometheus
management.metrics.distribution.percentiles-histogram.http.server.requests=true
management.observations.key-values.application=unicorn-spring-ai-agent

## Percentiles Histogram
management.metrics.distribution.percentiles-histogram.gen_ai.client.operation=true
management.metrics.distribution.percentiles-histogram.db.vector.client.operation=true
management.metrics.distribution.percentiles-histogram.spring.ai.chat.client=true
management.metrics.distribution.percentiles-histogram.spring.ai.tool=true
```

### Environment Variables

For production deployment, set these environment variables:

```bash
export SPRING_DATASOURCE_URL=jdbc:postgresql://your-db-host:5432/unicorn_agent
export SPRING_DATASOURCE_PASSWORD=your-secure-password
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
```

## Observability

The application includes comprehensive observability features:

### Metrics

- **Prometheus metrics** exposed at `/actuator/prometheus`
- **AI-specific metrics** for token usage, response times, and tool calls
- **Database metrics** for vector operations and chat memory
- **HTTP metrics** for web requests

### Logs

- **Structured logging** with AI-specific context
- **Prompt and completion logging** for debugging
- **Tool execution logging** for monitoring external calls
- **Error logging** with detailed context

### Health Checks

- **Application health** at `/actuator/health`
- **Database connectivity** checks
- **AI model availability** checks

## Deployment

### Docker Deployment

1. Build the Docker image:
   ```bash
   mvn spring-boot:build-image -Dspring-boot.build-image.imageName=unicorn-ai-agent:latest
   ```

2. Run with Docker Compose:
   ```yaml
   version: '3.8'
   services:
     postgres:
       image: pgvector/pgvector:pg16
       environment:
         POSTGRES_DB: unicorn_agent
         POSTGRES_USER: postgres
         POSTGRES_PASSWORD: postgres
       ports:
         - "5432:5432"

     app:
       image: unicorn-ai-agent:latest
       environment:
         SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/unicorn_agent
         SPRING_DATASOURCE_PASSWORD: postgres
       ports:
         - "8080:8080"
       depends_on:
         - postgres
   ```

### AWS Deployment

The application is designed to run on AWS with the following services:

- **Amazon EKS**: Container orchestration
- **Amazon RDS**: PostgreSQL with pgvector
- **Amazon Bedrock**: AI model hosting
- **Amazon CloudWatch**: Observability and monitoring

## Usage Examples

### Basic Chat

```bash
curl -X POST http://localhost:8080/api/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello, tell me about Unicorn Rentals"}'
```

### Weather Query

```bash
curl -X POST http://localhost:8080/api/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is the weather like in San Francisco on 2024-12-25?"}'
```

### DateTime Query

```bash
curl -X POST http://localhost:8080/api/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What time is it in Tokyo?"}'
```

### Adding Knowledge

```bash
curl -X POST http://localhost:8080/api/load \
  -H "Content-Type: text/plain" \
  -d "Unicorn Rentals offers premium unicorn rental services with 24/7 support and magical insurance coverage."
```

## Best Practices

### AI Integration Best Practices

1. **System Prompts**: Use clear, specific system prompts to guide AI behavior
2. **Memory Management**: Limit memory size to prevent token overflow (configured to 20 messages)
3. **Error Handling**: Implement retry logic for API throttling and failures
4. **Tool Integration**: Provide detailed descriptions for tools to ensure proper use
5. **RAG Implementation**: Use appropriate chunk sizes and overlap for document indexing

### Spring AI Best Practices

1. **ChatClient Builder**: Use the builder pattern for configuring the ChatClient
2. **Advisors**: Use advisors to extend the ChatClient's capabilities
3. **Tool Annotations**: Use detailed descriptions in @Tool annotations
4. **Vector Store**: Use appropriate dimensions (1024) and similarity metrics for embeddings
5. **Streaming**: Implement streaming for better user experience

### Security Best Practices

1. **Environment Variables**: Store sensitive configuration in environment variables
2. **Database Security**: Use connection pooling and proper authentication
3. **API Security**: Implement rate limiting and authentication for production
4. **Input Validation**: Validate and sanitize user inputs
5. **Logging**: Avoid logging sensitive information

## Troubleshooting

### Common Issues

1. **Database Connection Issues**
   - Ensure PostgreSQL is running and accessible
   - Verify pgvector extension is installed
   - Check connection string and credentials

2. **AWS Bedrock Access Issues**
   - Verify AWS credentials are configured
   - Ensure proper IAM permissions for Bedrock
   - Check model availability in your region

3. **Memory Issues**
   - Monitor JVM heap usage
   - Adjust memory settings if needed
   - Consider reducing chat memory window size

4. **Tool Execution Issues**
   - Check network connectivity for external APIs
   - Verify API keys and rate limits
   - Review tool descriptions for clarity

### Debug Mode

Enable debug logging for troubleshooting:

```properties
logging.level.org.springframework.ai=DEBUG
logging.level.com.unicorn.agent=DEBUG
```

## Future Enhancements

- **User Authentication**: Add user management and session handling
- **Multi-tenant Support**: Support multiple organizations
- **Advanced RAG**: Implement hybrid search and re-ranking
- **More Tools**: Add integration with more external services
- **Fine-tuning**: Support for custom model fine-tuning
- **Real-time Collaboration**: Multi-user chat sessions
- **Mobile App**: Native mobile application
- **Voice Interface**: Speech-to-text and text-to-speech

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

### Code Style

- Follow Java coding conventions
- Use meaningful variable and method names
- Add JavaDoc comments for public methods
- Write unit tests for new features

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions and support:

- Create an issue in the GitHub repository
- Check the Spring AI documentation
- Review AWS Bedrock documentation
- Consult the PostgreSQL and pgvector documentation
