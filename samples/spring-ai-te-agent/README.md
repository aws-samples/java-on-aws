# Spring AI Travel & Expense Agent

A comprehensive AI-powered agent ecosystem built with Spring AI framework, demonstrating modern AI application patterns including RAG, persistent memory, tool integration, and microservices communication via Model Context Protocol (MCP).

## Overview

The ecosystem consists of three microservices that work together:

1. **[AI Agent](ai-agent/README.md)** - Central AI assistant with chat interface, document analysis, and RAG capabilities
2. **[Travel Service](travel/README.md)** - Hotel and flight booking service with MCP integration
3. **[Backoffice Service](backoffice/README.md)** - Expense management and currency conversion service with MCP integration

The AI Agent connects to Travel and Backoffice services through MCP, enabling it to book travel, manage expenses, and provide comprehensive business assistance.

## Quick Start

### Prerequisites
- Java 21+
- Maven 3.8+
- Docker (for Testcontainers)
- AWS account with Amazon Bedrock access

### Running the Services

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

3. **Start AI Agent** (port 8080):
   ```bash
   cd ai-agent/
   mvn spring-boot:test-run
   ```

4. **Access the application**:
   ```
   http://localhost:8080
   ```

Each service uses Testcontainers for automatic database setup - no manual configuration required!

## Services

### AI Agent
- **Chat interface** with persistent memory using JDBC
- **Document analysis** (PDF, images) with multimodal AI models
- **RAG implementation** using pgvector for knowledge base
- **Tool integration** and MCP client for microservices
- **Models**: OpenAI GPT-OSS-120B, Claude Sonnet 4, Amazon Nova

### Travel Service
- **Hotel & flight booking** with comprehensive search
- **Airport information** and weather forecasts
- **MCP server** exposing travel tools to AI Agent

### Backoffice Service
- **Expense management** with approval workflows
- **Currency conversion** with real-time exchange rates
- **MCP server** exposing business tools to AI Agent

## Technology Stack

- **Spring Boot 3.5.7** - Core framework
- **Spring AI 1.0.3** - AI integration framework
- **Amazon Bedrock** - AI model provider
- **PostgreSQL 16** with pgvector extension
- **Testcontainers 1.21.3** - Development and testing
- **Model Context Protocol** - Microservices communication

## Key Features Demonstrated

- **Persistent Chat Memory** - JDBC-based conversation history
- **RAG Implementation** - Vector search with pgvector
- **Multimodal AI** - Text and document analysis
- **Tool Integration** - Custom tools and MCP protocol
- **Microservices Architecture** - Distributed AI capabilities
- **Testcontainers** - Seamless development experience

## AWS Configuration

Configure AWS credentials for Bedrock access:
```bash
aws configure
```

Ensure access to required models:
- `openai.gpt-oss-120b-1:0`
- `global.anthropic.claude-sonnet-4-20250514-v1:0`
- `us.amazon.nova-pro-v1:0` (optional)

## Documentation

- [AI Agent Documentation](ai-agent/README.md) - Detailed setup and architecture
- [Travel Service Documentation](travel/README.md) - Travel booking API
- [Backoffice Service Documentation](backoffice/README.md) - Expense management API
