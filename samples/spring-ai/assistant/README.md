# Spring AI Office Assistant

A comprehensive AI-powered office assistant built with Spring AI framework, featuring multimodal chat capabilities, document analysis, RAG (Retrieval-Augmented Generation), persistent memory, and tool integration.

## 🏗️ Architecture Overview

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Spring AI Assistant                      │
├─────────────────────────────────────────────────────────────┤
│  Web Layer (Thymeleaf + REST API)                           │
│  ├── WebController (/)                                      │
│  └── ChatController (/api/chat, /api/rag-load)              │
├─────────────────────────────────────────────────────────────┤
│  AI Integration Layer                                       │
│  ├── Amazon Bedrock (Claude Sonnet 4)                       │
│  ├── Chat Memory (PostgreSQL-backed)                        │
│  ├── Vector Store (pgvector)                                │
│  ├── RAG System (Document Retrieval)                        │
│  └── Tools Integration (DateTime, MCP Clients)              │
├─────────────────────────────────────────────────────────────┤
│  Data Layer                                                 │
│  ├── PostgreSQL Database (assistant_db)                     │
│  ├── Chat Memory Repository                                 │
│  └── Vector Embeddings (Titan v2)                           │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack

- **Framework**: Spring Boot 3.5.3 with Spring AI 1.0.0
- **Java Version**: 21
- **AI Provider**: Amazon Bedrock (Claude Sonnet 4)
- **Database**: PostgreSQL 16 with pgvector extension
- **Embeddings**: Amazon Titan Embed Text v2
- **Frontend**: Thymeleaf + Tailwind CSS
- **Build Tool**: Maven

## 🎯 Purpose and Features

### Primary Capabilities

1. **Multimodal Chat Interface**
   - Text-based conversations with persistent memory
   - Document analysis (PDF, JPG, JPEG, PNG)
   - File upload and automatic analysis
   - Real-time web interface

2. **Document Intelligence**
   - Expense report analysis and policy compliance checking
   - Receipt and invoice processing
   - Travel document analysis
   - Structured data extraction

3. **RAG (Retrieval-Augmented Generation)**
   - Knowledge base integration
   - Document embedding and retrieval
   - Context-aware responses
   - Policy and procedure queries

4. **Persistent Memory**
   - Conversation history across sessions
   - User context retention
   - JDBC-backed chat memory

5. **Tool Integration**
   - DateTime utilities
   - MCP (Model Context Protocol) client support
   - Extensible tool framework

## 🚀 Getting Started

### Prerequisites

- Java 21+
- PostgreSQL 16 with pgvector extension
- AWS Account with Bedrock access
- Maven 3.6+

### Environment Setup

1. **Set AWS Region** (Required):
   ```bash
   export AWS_REGION=us-east-1
   ```

2. **Configure AWS Credentials**:
   ```bash
   # Option 1: AWS CLI
   aws configure

   # Option 2: Environment variables
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   ```

3. **Database Setup**:
   - Start the database from the `../database` directory
   - PostgreSQL 16 with pgvector extension required
   - Default connection: `localhost:5432/assistant_db` (postgres/postgres)
   - See [Database Setup](#database-setup) section below

### Database Setup

Before running the application, you need to start the PostgreSQL database with pgvector extension:

```bash
# Navigate to the database directory (one folder up from assistant)
cd ../database

# Start the database using the provided script (keep this terminal open)
./start-postgres.sh
```

**Note**: Keep the database terminal open as it runs in the foreground. You'll need a separate terminal to run the application.

This will start:
- PostgreSQL 16 with pgvector extension
- pgAdmin web interface at http://localhost:8090
- Creates `assistant_db`, `backoffice_db`, `travel_db`, and `postgres` databases

For detailed database setup instructions, see the [database README](../database/README.md).

### Running the Application

```bash
# In a new terminal, from the assistant directory, run the application
./mvnw spring-boot:run
```

The application will be available at:
- **Web Interface**: http://localhost:8080
- **API Endpoints**: http://localhost:8080/api/*

### Loading RAG Data

To populate the knowledge base with documents:

```bash
# Load travel and expenses policy
curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @./travel_and_expenses_policy.md \
  http://localhost:8080/api/rag-load

# Load any text document
curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @./your-document.txt \
  http://localhost:8080/api/rag-load
```

## 📚 Spring AI Framework Reference

For comprehensive documentation, visit: [Spring AI Reference Documentation](https://docs.spring.io/spring-ai/reference/)

### Key Spring AI Concepts

#### 🗣️ [Chat](https://docs.spring.io/spring-ai/reference/api/chat.html)
The foundation of conversational AI interactions.
- **ChatClient**: Fluent API for building chat interactions
- **ChatModel**: Interface for different AI providers
- **Message Types**: System, User, Assistant, Tool messages
- **Streaming Support**: Real-time response streaming

```java
// Example from our ChatController
var chatResponse = chatClient
    .prompt()
    .user(prompt)
    .advisors(advisor -> advisor.param(ChatMemory.CONVERSATION_ID, conversationId))
    .call().chatResponse();
```

#### 🎨 [Multimodal](https://docs.spring.io/spring-ai/reference/api/multimodal.html)
Support for text, image, and document processing.
- **Media Support**: Images (JPG, PNG), Documents (PDF)
- **Vision Models**: Document analysis and image understanding
- **File Processing**: Base64 encoding and MIME type handling

```java
// Multimodal processing in our application
userSpec.text(prompt);
userSpec.media(mimeType, resource);
```

#### 🧠 [Memory](https://docs.spring.io/spring-ai/reference/api/chat-memory.html)
Persistent conversation context and history.
- **Chat Memory**: Conversation state management
- **JDBC Repository**: Database-backed memory storage
- **Message Windows**: Configurable conversation length
- **Memory Advisors**: Automatic context injection

```java
// Memory configuration
var chatMemory = MessageWindowChatMemory.builder()
    .chatMemoryRepository(chatMemoryRepository)
    .maxMessages(20)
    .build();
```

#### 🔍 [RAG (Retrieval-Augmented Generation)](https://docs.spring.io/spring-ai/reference/api/vectordbs.html)
Knowledge retrieval and context enhancement.
- **Vector Stores**: Document embedding storage
- **Similarity Search**: Semantic document retrieval
- **Question-Answer Advisors**: Automatic context injection
- **Embedding Models**: Text vectorization

```java
// RAG implementation
QuestionAnswerAdvisor.builder(vectorStore).build()
```

#### 🛠️ [Tools](https://docs.spring.io/spring-ai/reference/api/tools.html)
Function calling and external system integration.
- **Tool Annotations**: `@Tool` for function definitions
- **Tool Callbacks**: Dynamic tool registration
- **Function Calling**: AI-driven tool selection
- **Parameter Binding**: Automatic argument mapping

```java
// Tool example
@Tool(description = "Get the current date and time")
public String getCurrentDateTime(String timeZone) {
    return ZonedDateTime.now(ZoneId.of(timeZone))
            .format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
}
```

#### 🔌 [MCP Clients](https://docs.spring.io/spring-ai/reference/api/mcp.html)
Model Context Protocol for external tool integration.
- **Protocol Support**: Standardized tool communication
- **Server Connections**: External service integration
- **Tool Discovery**: Dynamic capability detection
- **Callback Providers**: Tool execution handling

## 🔧 Configuration

### Application Properties

Key configuration options in `application.properties`:

```properties
# AI Model Configuration
spring.ai.bedrock.converse.chat.options.model=us.anthropic.claude-sonnet-4-20250514-v1:0
spring.ai.bedrock.converse.chat.options.max-tokens=10000

# Database Configuration
spring.datasource.url=jdbc:postgresql://localhost:5432/assistant_db
spring.ai.chat.memory.repository.jdbc.initialize-schema=always

# Vector Store Configuration
spring.ai.vectorstore.pgvector.initialize-schema=true
spring.ai.vectorstore.pgvector.dimensions=1024

# Embeddings Configuration
spring.ai.bedrock.titan.embedding.model=amazon.titan-embed-text-v2:0
```

### Model Options

Available Bedrock models (configure in application.properties):
- `us.anthropic.claude-sonnet-4-20250514-v1:0` (Default - Latest Claude)
- `amazon.nova-pro-v1:0` (Amazon Nova Pro)
- `eu.amazon.nova-lite-v1:0` (Amazon Nova Lite - EU)
- `eu.anthropic.claude-3-7-sonnet-20250219-v1:0` (Claude 3.7 Sonnet - EU)

## 📁 Project Structure

```
src/main/java/com/example/assistant/
├── AssistantApplication.java          # Spring Boot main class
├── ChatController.java            # REST API endpoints
├── WebController.java             # Web interface controller
└── DateTimeTools.java             # Tool implementation

src/main/resources/
├── application.properties         # Configuration
├── document_analysis_prompt.md    # Document analysis template
└── templates/
    └── chat.html                  # Web interface

travel_and_expenses_policy.md      # Sample RAG document
```

## 🔌 API Endpoints

### Chat API
```http
POST /api/chat
Content-Type: application/json

{
  "prompt": "Your question here",
  "fileBase64": "base64_encoded_file_data",
  "fileName": "document.pdf"
}
```

> fileBase64 and fileName can be null

### RAG Data Loading
```http
POST /api/rag-load
Content-Type: text/plain

Document content to be indexed...
```

### Web Interface
```http
GET /
```
Interactive chat interface with file upload support.

## 🎛️ Advanced Features

### Document Analysis Pipeline

1. **File Upload**: Supports PDF, JPG, JPEG, PNG
2. **Automatic Analysis**: Uses specialized prompts for document types
3. **Policy Compliance**: Validates against company policies
4. **Structured Extraction**: Extracts key information fields
5. **Approval Workflow**: Determines required approval levels

### Memory Management

- **Conversation Persistence**: Maintains context across sessions
- **User Identification**: Supports multi-user conversations
- **Message Windowing**: Configurable conversation length (20 messages default)
- **Database Storage**: PostgreSQL-backed for reliability

### RAG System

- **Document Embedding**: Automatic vectorization of loaded content
- **Semantic Search**: Context-aware document retrieval
- **Policy Integration**: Company policy and procedure queries
- **Dynamic Context**: Automatic context injection into conversations

## 🔍 Troubleshooting

### Common Issues

1. **AWS Region Not Set**:
   ```bash
   export AWS_REGION=us-east-1
   ```

2. **Database Connection Issues**:
   - Start the database: `cd ../database && ./start-postgres.sh`
   - Verify PostgreSQL is running on port 5432
   - Check database credentials in application.properties
   - Ensure pgvector extension is installed (handled by database setup)

3. **Bedrock Access Issues**:
   - Verify AWS credentials are configured
   - Check Bedrock model access in your AWS region
   - Ensure proper IAM permissions

4. **File Upload Issues**:
   - Check file size limits
   - Verify supported file types (PDF, JPG, JPEG, PNG)
   - Ensure proper base64 encoding

### Logging

Enable debug logging for troubleshooting:
```properties
logging.level.org.springframework.ai=DEBUG
logging.level.com.example.assistant=DEBUG
```

## 🚀 Development and Extension

### Adding New Tools

1. Create a new tool class:
```java
@Component
public class MyCustomTool {
    @Tool(description = "Description of what this tool does")
    public String myToolMethod(String parameter) {
        // Tool implementation
        return "Result";
    }
}
```

2. Register in ChatController constructor:
```java
.defaultTools(new DateTimeTools(), new MyCustomTool())
```

### Extending Document Analysis

1. Modify `document_analysis_prompt.md` for new document types
2. Add new MIME type support in `getMimeType()` method
3. Extend policy validation logic

### Adding New RAG Sources

```bash
# Load additional documents
curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @./samples/travel_and_expenses_policy.md \
  http://localhost:8080/api/rag-load
```

---

For more information about Spring AI capabilities, visit the [official documentation](https://docs.spring.io/spring-ai/reference/).
