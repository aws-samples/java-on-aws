# Spring AI Agent

A comprehensive AI-powered agent built with Spring AI framework, featuring multimodal chat capabilities, document analysis, RAG (Retrieval-Augmented Generation), persistent memory, tool integration, and Model Context Protocol (MCP) client functionality.

## Features

- **Multimodal Chat Interface** - Text conversations with document upload support (PDF, JPG, JPEG, PNG)
- **Persistent Memory** - JDBC-based chat memory for conversation continuity across sessions
- **RAG Implementation** - Knowledge base integration using pgvector for document retrieval
- **Tool Integration** - Custom function calling capabilities for extended functionality
- **MCP Client** - Connects to Travel and Backoffice services via Model Context Protocol
- **Multiple AI Models** - Support for Claude Sonnet 4 and Amazon Nova

## Quick Start

### Prerequisites

- Java 21+
- Maven 3.8+
- Docker (for Testcontainers)
- AWS account with Amazon Bedrock access

### Running the Application

```bash
mvn spring-boot:test-run
```

The application will start on port 8080 with automatic PostgreSQL setup via Testcontainers.

Access the web interface at: http://localhost:8080

## Configuration

### AWS Bedrock Setup

Configure AWS credentials and region:

```bash
aws configure
export AWS_REGION=us-east-1
```

Ensure access to required models:

- `global.anthropic.claude-sonnet-4-20250514-v1:0`
- `us.amazon.nova-pro-v1:0` (optional)

## Architecture

The AI Agent follows a layered architecture:

- **Web Layer** - Thymeleaf templates and REST controllers
- **Service Layer** - Chat service with memory and RAG integration
- **Integration Layer** - MCP client for external services
- **Data Layer** - PostgreSQL with pgvector extension

## Technology Stack

- **Spring Boot 3.5.7** - Core framework
- **Spring AI 1.0.3** - AI integration framework
- **Amazon Bedrock** - AI model provider
- **PostgreSQL 16** with pgvector extension
- **Testcontainers 1.21.3** - Development and testing
- **Thymeleaf** - Web templating engine
