# Spring AI Agent

A comprehensive AI-powered agent built with Spring AI framework, featuring weather forecasting capabilities and secure OAuth integration.

## Related Documentation

This project is part of a larger microservices ecosystem:

- [Weather Service Documentation](../weather/README.md) - Weather forecast service with global coverage

## Project Overview

### Description

The Spring AI Agent is a demonstration of how to build modern AI-powered applications using the Spring AI framework. It provides weather forecasting capabilities through:

- Weather forecasts for any city worldwide
- Integration with external weather APIs
- Model Context Protocol (MCP) client for connecting to weather services
- Secure OAuth authentication and authorization

The application serves as the central component in a microservices architecture, connecting to the Weather service through the Model Context Protocol (MCP).

### Purpose

This application serves as:

1. A reference implementation for Spring AI integration with weather services
2. A demonstration of secure AI application patterns with OAuth
3. A practical example of building weather assistants with Spring Boot
4. A showcase for integrating with Amazon Bedrock and weather APIs

### Technology Stack

- **Java 21**: Latest LTS version with modern language features
- **Spring Boot 3.5.7**: Core framework for building the application
- **Spring AI 1.0.3**: AI integration framework
- **Spring Security**: OAuth 2.0 authentication and authorization
- **Amazon Bedrock**: AI model provider (Claude Sonnet 4)
- **Docker**: Containerization for application

## Security

### OAuth 2.0 Integration

The application implements OAuth 2.0 for secure authentication and authorization:

- **Authorization Server**: Integrated OAuth 2.0 authorization server
- **Resource Protection**: Secured API endpoints with JWT tokens
- **Token Validation**: Automatic JWT token validation and user context

## Getting Started

### Prerequisites

- Java 21 or higher
- Maven 3.8 or higher
- AWS account with Amazon Bedrock access

### Prerequisites for Full Functionality

Before starting the AI agent, ensure the required services are running:

1. **Start Authorization Server** (port 9000):
   ```bash
   cd ../authorization-server/
   mvn spring-boot:run
   ```

2. **Start Weather Service** (port 8083):
   ```bash
   cd ../weather/
   mvn spring-boot:run
   ```

These services provide OAuth authentication and weather forecasting tools that the AI agent uses.

#### Running the AI Agent

```bash
cd ai-agent/
mvn spring-boot:run
```

This will:
- Configure secure endpoints for weather data access
- Connect to the weather service via MCP for authenticated users only
- Connect to the authorization server for OAuth authentication
- Start the application on port 8080

#### Access Points

Once all applications are running, you can access:

- **Main Application**: `http://localhost:8080/`

### AWS Configuration

1. Configure AWS credentials:
   ```bash
   aws configure
   ```

2. Ensure you have access to Amazon Bedrock and the required models (Claude Sonnet 4).

### Building and Running the Application

1. **Standard Build and Run:**
   ```bash
   cd ai-agent/
   mvn clean package
   mvn spring-boot:run
   ```

2. The application will be available at:
   ```
   http://localhost:8080/
   ```

### Authentication Flow

1. Navigate to `http://localhost:9000/` (authorization server)
2. Authenticate with your credentials
3. Use the authorization code to obtain an access token
4. Access weather endpoints with the Bearer token

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
