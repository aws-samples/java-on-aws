# Spring AI Travel Service

A comprehensive travel management service built with Spring Boot, providing hotel and flight booking capabilities with AI integration through Model Context Protocol (MCP).

## Features

- **Hotel Management** - Search, book, and manage hotel reservations
- **Flight Management** - Search, book, and manage flight bookings
- **Airport Information** - Comprehensive airport data and services
- **MCP Server** - Exposes travel tools to AI agents via Model Context Protocol
- **RESTful API** - Complete REST API for travel operations

## Quick Start

### Prerequisites

- Java 21+
- Maven 3.8+
- Docker (for Testcontainers)

### Running the Application

```bash
mvn spring-boot:test-run
```

The application will start on port 8082 with automatic PostgreSQL setup via Testcontainers.

## API Endpoints

### Hotels

- `GET /api/hotels` - Search hotels
- `POST /api/hotels/{id}/book` - Book a hotel
- `GET /api/bookings/hotels` - List hotel bookings

### Flights

- `GET /api/flights` - Search flights
- `POST /api/flights/{id}/book` - Book a flight
- `GET /api/bookings/flights` - List flight bookings

### Airports

- `GET /api/airports` - List airports
- `GET /api/airports/{code}` - Get airport details

## MCP Integration

The service exposes travel tools via Model Context Protocol on `/mcp` endpoint:

- `search_hotels` - Search for available hotels
- `book_hotel` - Book a hotel reservation
- `search_flights` - Search for available flights
- `book_flight` - Book a flight reservation
- `get_airports` - Get airport information

## Technology Stack

- **Spring Boot 3.5.7** - Core framework
- **Spring Data JPA** - Data persistence
- **PostgreSQL 16** - Database
- **Testcontainers 1.21.3** - Development and testing
- **Model Context Protocol** - AI agent integration
