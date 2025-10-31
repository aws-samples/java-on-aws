# Spring AI Agent

A comprehensive AI-powered agent built with Spring AI framework, featuring multimodal chat capabilities, document analysis, RAG (Retrieval-Augmented Generation), persistent memory, tool integration, and Testcontainers support for development.

## Related Documentation

This project is part of a larger microservices ecosystem:

- [Travel Service Documentation](../travel/README.md) - Travel booking service with hotel and flight management
- [Backoffice Service Documentation](../backoffice/README.md) - Expense management and currency conversion service

## Project Overview

### Description

The Spring AI Agent is a demonstration of how to build modern AI-powered applications using the Spring AI framework. It provides a complete set of capabilities for interacting with AI models, including:

- Text-based conversations with persistent memory using JDBC-based chat memory
- Document analysis (PDF, JPG, JPEG, PNG) with multimodal AI models
- Retrieval-Augmented Generation (RAG) for knowledge base integration using pgvector
- Tool integration for enhanced capabilities (DateTime tools)
- Model Context Protocol (MCP) client for connecting to external services
- Testcontainers integration for seamless development and testing

The application serves as the central component in a microservices architecture, connecting to specialized services like the Travel and Backoffice applications through the Model Context Protocol (MCP).

### Purpose

This application serves as:

1. A reference implementation for Spring AI integration in enterprise applications
2. A demonstration of key AI application patterns (RAG, memory, tools, MCP)
3. A practical example of building AI assistants with Spring Boot
4. A showcase for integrating with Amazon Bedrock and other AI services

### Technology Stack

- **Java 21**: Latest LTS version with modern language features
- **Spring Boot 3.5.7**: Core framework for building the application
- **Spring AI 1.0.3**: AI integration framework
- **Amazon Bedrock**: AI model provider (OpenAI GPT-OSS-120B, Claude Sonnet 4, Nova Pro/Premier)
- **PostgreSQL 16**: Database with pgvector extension for vector operations
- **Testcontainers 1.21.3**: Integration testing with containerized dependencies
- **Thymeleaf**: Server-side templating for the web interface
- **Docker**: Containerization for database and application

## Getting Started

### Prerequisites

- Java 21 or higher
- Maven 3.8 or higher
- Docker (for Testcontainers)
- AWS account with Amazon Bedrock access

### Development with Testcontainers

The application uses Testcontainers for seamless development and testing. No manual database setup is required!

#### Prerequisites for Full Functionality

Before starting the AI agent, ensure the dependent services are running:

1. **Start Travel Service** (port 8081):
   ```bash
   cd travel/
   mvn spring-boot:test-run
   ```

2. **Start Backoffice Service** (port 8082):
   ```bash
   cd backoffice/
   mvn spring-boot:test-run
   ```

These services provide MCP tools that the AI agent can use for travel booking and expense management.

#### Running the AI Agent

```bash
cd ai-agent/
mvn spring-boot:test-run
```

This will:
- Automatically start a PostgreSQL container with pgvector extension
- Initialize the `ai_agent_db` database
- Configure the application to use the containerized database
- Connect to the travel and backoffice services via MCP
- Start the application on port 8080

The container will be named `ai-agent-postgres` for easy identification.

### AWS Configuration

1. Configure AWS credentials:
   ```bash
   aws configure
   ```

2. Ensure you have access to Amazon Bedrock and the required models (Claude Sonnet 4).

### Building and Running the Application

1. **With Testcontainers (Recommended for Development):**
   ```bash
   cd ai-agent/
   mvn spring-boot:test-run
   ```

2. **Traditional Build and Run:**
   ```bash
   cd ai-agent/
   mvn clean package
   mvn spring-boot:run
   ```

3. The application will be available at:
   ```
   http://localhost:8080
   ```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
