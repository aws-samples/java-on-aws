# Spring AI Microservices Ecosystem

This repository contains a comprehensive ecosystem of Spring AI-powered microservices that demonstrate how to build modern AI applications using the Spring AI framework.

## Overview

The ecosystem consists of three main applications and a shared database infrastructure:

1. **AI Assistant** - The central application that provides a chat interface with AI capabilities
2. **Travel Service** - A specialized service for travel booking and management
3. **Backoffice Service** - A specialized service for expense management and currency conversion
4. **Database Infrastructure** - Shared PostgreSQL database with pgvector extension

These applications work together through the Model Context Protocol (MCP), allowing the AI Assistant to leverage specialized capabilities from the Travel and Backoffice services.

## Architecture

The overall architecture follows a microservices pattern with the AI Assistant as the central component:

![Assistant Architecture](assistant/docs/architecture.png)

The AI Assistant connects to the Travel and Backoffice services through the MCP protocol, allowing it to:
- Search for and book hotels and flights (via Travel service)
- Create and manage expenses (via Backoffice service)
- Convert currencies (via Backoffice service)

## Projects

### [AI Assistant](assistant/README.md)

The AI Assistant is the central application in the ecosystem, providing:

- Text-based conversations with persistent memory
- Document analysis (PDF, JPG, JPEG, PNG)
- Retrieval-Augmented Generation (RAG) for knowledge base integration
- Tool integration for enhanced capabilities
- Model Context Protocol (MCP) client for connecting to external services

**Key Technologies:**
- Spring AI with Amazon Bedrock (Claude Sonnet 4)
- PostgreSQL with pgvector for vector embeddings
- Thymeleaf web interface

![assistant-ui](assistant/docs/assistant-ui.png)

### [Travel Service](travel/README.md)

The Travel service provides specialized functionality for travel management:

- Hotel search and booking
- Flight search and booking
- Airport information
- Weather forecasts for destinations
- MCP server for AI integration

**Key Technologies:**
- Spring Boot with Spring Data JPA
- PostgreSQL for data storage
- Spring AI MCP Server for AI integration

### [Backoffice Service](backoffice/README.md)

The Backoffice service provides specialized functionality for business operations:

- Expense management (create, track, update, approve)
- Currency conversion with real-time exchange rates
- MCP server for AI integration

**Key Technologies:**
- Spring Boot with Spring Data JPA
- PostgreSQL for data storage
- Spring AI MCP Server for AI integration

### [Database Infrastructure](database/README.md)

The shared database infrastructure provides:

- PostgreSQL 16 with pgvector extension for vector embeddings
- Multiple databases for different application domains
- pgAdmin web interface for database management

## Getting Started

1. Start the database infrastructure:
   ```bash
   cd database/
   ./start-postgres.sh
   ```

2. Start the Travel service:
   ```bash
   cd travel/
   mvn spring-boot:run
   ```

3. Start the Backoffice service:
   ```bash
   cd backoffice/
   mvn spring-boot:run
   ```

4. Start the AI Assistant:
   ```bash
   cd assistant/
   mvn spring-boot:run
   ```

5. Access the AI Assistant web interface:
   ```
   http://localhost:8080
   ```

## Key Spring AI Features

This ecosystem demonstrates several key features of the [Spring AI framework](https://docs.spring.io/spring-ai/reference/index.html):

1. **AI Integration** - Using Spring AI to integrate with AI models (Amazon Bedrock)
2. **System Prompts** - Configuring AI behavior with system prompts
3. **Chat Memory** - Implementing persistent conversation memory
4. **RAG** - Implementing Retrieval-Augmented Generation for knowledge base integration
5. **Tool Integration** - Extending AI capabilities with custom tools
6. **MCP** - Using the Model Context Protocol for microservices integration

For more details on each feature, refer to the [AI Assistant documentation](assistant/README.md).

## Prerequisites

- Java 21 or higher
- Maven 3.8 or higher
- Docker and Docker Compose
- AWS account with Amazon Bedrock access

## License

This project is licensed under the MIT License - see the LICENSE file for details.
