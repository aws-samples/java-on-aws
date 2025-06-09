# Spring AI Simple Chat Client

A lightweight Spring Boot application demonstrating the integration of Spring AI with Amazon Bedrock to create a simple chat API. 

## Features

- REST API endpoints for AI chat interactions
- Support for both synchronous and streaming responses
- Custom tool integration
- Integration with Amazon Bedrock's Claude 3 Sonnet model

## Prerequisites

- Java 21
- Maven
- AWS account with access to Amazon Bedrock
- AWS credentials configured locally

## Configuration

The application is configured to use Amazon Bedrock's Claude 3 Sonnet model in the EU West 1 region. You can modify these settings in `application.properties`:

```properties
spring.application.name=agents
spring.ai.bedrock.aws.region=eu-west-1
spring.ai.bedrock.converse.chat.options.model=eu.anthropic.claude-3-7-sonnet-20250219-v1:0
```

## Building and Running

```bash
mvn spring-boot:run
```

The application will start on port 8080 by default.

## API Endpoints

### 1. Synchronous Chat Endpoint

Send a prompt and receive a complete response:

```bash
curl -XPOST 'http://localhost:8080/ai' \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Tell me about Spring AI in 2 sentences."}'
```

### 2. Streaming Chat Endpoint

Send a prompt and receive the response as a stream (useful for real-time UI updates):

```bash
curl -XPOST -N 'http://localhost:8080/ai/stream' \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Who is George Mallory?"}'
```

### 3. With tool use

curl -XPOST -N 'http://localhost:8080/ai/stream' \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is the current date and time?"}'

## Project Structure

- `ChatController.java`: Defines the REST endpoints for chat interactions
- `PromptRequest.java`: Simple record class for the request payload
- `DateTimeTools.java`: Custom tool that provides date/time information to the AI
- `AgentsApplication.java`: Spring Boot application entry point
