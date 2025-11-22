# Spring AI Weather Service

A dedicated weather forecast microservice built with Spring Boot and Spring AI, providing weather information through REST API and Model Context Protocol (MCP) integration.

## Project Overview

### Description

The Spring AI Weather Service is a specialized microservice that provides weather forecast capabilities for the AI agent ecosystem. It offers:

- Weather forecasts for any city worldwide
- Historical and future weather data
- Integration with external weather APIs
- MCP server for AI agent integration

The service follows Domain-Driven Design (DDD) principles and showcases best practices for building Spring Boot microservices with AI capabilities.

### Purpose

This service serves as:

1. A dedicated weather data provider for the AI agent ecosystem
2. A demonstration of microservice architecture with Spring AI
3. An example of external API integration and caching strategies
4. A showcase for MCP server implementation

### Technology Stack

- **Java 21**: Latest LTS version with modern language features
- **Spring Boot 3.5.7**: Core framework for building the application
- **Spring AI 1.0.3**: AI integration with Model Context Protocol (MCP)
- **Spring WebFlux**: Reactive programming for external API calls
- **Open-Meteo API**: External weather data provider
- **Docker**: Containerization for application deployment

## Quick Start

```bash
# Clone and navigate to the project
cd weather/

# Run the service
mvn spring-boot:run

# Application available at http://localhost:8081
```

## Getting Started

### Prerequisites

- Java 21 or higher
- Maven 3.8 or higher
- Internet connection for external weather API calls

### Running the Application

#### Development Mode

```bash
cd weather/
mvn spring-boot:run
```

This will start the weather service on http://localhost:8081

#### Building and Testing

1. Build the application:
   ```bash
   cd weather/
   mvn clean package
   ```

2. Run tests:
   ```bash
   mvn test
   ```

### Testing the API

Test the weather API endpoints:

```bash
# Get weather forecast for a city
curl "http://localhost:8081/api/weather?city=London&date=2025-11-01"

# Get weather for different cities
curl "http://localhost:8081/api/weather?city=New York&date=2025-11-01"
curl "http://localhost:8081/api/weather?city=Tokyo&date=2025-11-01"
```

## Architecture

The weather service follows a clean architecture with clear separation of concerns:

### Domain Model

The service is organized around the Weather domain with:

1. **Weather Forecasting**: Core business logic for weather data retrieval
2. **Location Services**: Geocoding and city resolution
3. **External Integration**: Weather API client abstraction

### Layered Architecture

1. **Controller Layer**: REST API endpoints
2. **Service Layer**: Business logic and external API coordination
3. **Client Layer**: External API integration with proper error handling
4. **Tools Layer**: AI-specific functionality exposed via MCP

### AI Integration

The service integrates with AI systems through:

1. **MCP Server**: Exposes weather functionality as AI tools
2. **Tool Annotations**: Marks methods for AI consumption
3. **Parameter Validation**: Ensures proper input handling
4. **Response Formatting**: Structures responses for AI consumption

## API Documentation

### Weather API

#### Get Weather Forecast
```
GET /api/weather?city={city}&date={date}
```
Parameters:
- `city`: Name of the city for weather forecast
- `date`: Date for the forecast in format yyyy-MM-dd (can be past, present, or future)

Response:
```
Weather for London, GB on 2025-11-01:
Min: 8.2 deg C, Max: 14.7 deg C
```

## AI Tools

The service exposes the following AI tools through the MCP server:

### Weather Tools
- `getWeatherForecast`: Get weather forecast for a city on a specific date

### Security

The AI tools methods are secured and require proper authentication to access the weather forecasting capabilities.

## Best Practices

The service demonstrates several best practices:

### Microservice Design
- Single responsibility principle
- Clear API boundaries
- Proper error handling
- External dependency abstraction

### API Design
- RESTful endpoints
- Consistent error responses
- Proper HTTP status codes
- Input validation

### External Integration
- Resilient API client design
- Timeout handling
- Proper error propagation
- Rate limiting considerations

### Testing
- Unit tests for business logic
- Integration tests for API endpoints
- Mock external dependencies
- Comprehensive error scenario testing

## Configuration

### Application Properties

The service can be configured through `application.properties`:

```properties
# Server configuration
server.port=8083

# Logging configuration
logging.level.com.example.weather=INFO
logging.level.org.springframework.web.reactive.function.client=DEBUG

# External API timeouts
weather.api.timeout=15s
```

## Integration with AI Agent

The weather service integrates with the AI agent through MCP:

1. **Start Weather Service** (port 8081):
   ```bash
   cd weather/
   mvn spring-boot:run
   ```

2. **Configure AI Agent**: Update the AI agent's MCP configuration to include the weather service endpoint

3. **Use Weather Tools**: The AI agent can now access weather forecasting capabilities through the exposed tools

## Future Enhancements

- Add weather alerts and notifications
- Implement caching for frequently requested locations
- Add more detailed weather information (humidity, wind, precipitation)
- Integrate with multiple weather data providers
- Add weather history and trends analysis
- Implement rate limiting and API key management
- Add monitoring and observability features

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.