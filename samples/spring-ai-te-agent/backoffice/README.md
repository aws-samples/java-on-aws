# Spring AI Backoffice Service

A comprehensive backoffice management service built with Spring Boot, providing expense management and currency conversion capabilities with AI integration through Model Context Protocol (MCP).

## Features

- **Expense Management** - Create, track, update, and approve expenses
- **Currency Conversion** - Real-time exchange rates and currency operations
- **Approval Workflows** - Multi-level expense approval processes
- **MCP Server** - Exposes business tools to AI agents via Model Context Protocol
- **RESTful API** - Complete REST API for backoffice operations

## Quick Start

### Prerequisites

- Java 21+
- Maven 3.8+
- Docker (for Testcontainers)

### Running the Application

```bash
mvn spring-boot:test-run
```

The application will start on port 8083 with automatic PostgreSQL setup via Testcontainers.

## API Endpoints

### Expenses

- `GET /api/expenses` - List expenses
- `POST /api/expenses` - Create expense
- `PUT /api/expenses/{id}` - Update expense
- `POST /api/expenses/{id}/approve` - Approve expense

### Currencies

- `GET /api/currencies` - List supported currencies
- `GET /api/currencies/rates` - Get exchange rates
- `POST /api/currencies/convert` - Convert between currencies

## MCP Integration

The service exposes business tools via Model Context Protocol on `/mcp` endpoint:

- `create_expense` - Create a new expense record
- `get_expenses` - Retrieve expense records
- `approve_expense` - Approve an expense
- `get_exchange_rate` - Get currency exchange rates
- `convert_currency` - Convert between currencies

## Technology Stack

- **Spring Boot 3.5.7** - Core framework
- **Spring Data JPA** - Data persistence
- **PostgreSQL 16** - Database
- **Testcontainers 1.21.3** - Development and testing
- **Model Context Protocol** - AI agent integration
