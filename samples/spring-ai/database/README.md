# Spring AI Database Setup

This directory contains the PostgreSQL database setup for the Spring AI application, combining databases from the agent and backoffice projects.

## Database Configuration

- **PostgreSQL Version**: 16 with pgvector extension
- **Container**: Single PostgreSQL container with 3 databases
- **Port**: 5432 (standard PostgreSQL port)
- **Username/Password**: postgres/postgres for all databases

## Databases

1. **assistant_db** - Main AI assistant database with pgvector extension for vector operations
2. **backoffice_db** - BackOffice application database
3. **travel_db** - Travel and expenses database

## pgAdmin Configuration

- **Version**: 9.5
- **Port**: 8090
- **URL**: http://localhost:8090
- **Login**: admin@admin.com / admin
- **Auto-configured**: All 3 databases are pre-configured and ready to use

## Usage

### Start the Database

```bash
cd /Users/bezsonov/sources/spring-ai/database
./start-postgres.sh
```

### Stop the Database

Press `Ctrl+C` in the terminal where the script is running, or run:

```bash
docker-compose down --volumes
```

### Connect to Databases

#### Via pgAdmin
1. Open http://localhost:8090
2. Login with admin@admin.com / admin
3. All databases will be available in the "Spring AI Databases" group

#### Via Command Line
```bash
# Connect to assistant_db (with pgvector)
psql -h localhost -p 5432 -U postgres -d assistant_db

# Connect to backoffice_db
psql -h localhost -p 5432 -U postgres -d backoffice_db

# Connect to travel_db
psql -h localhost -p 5432 -U postgres -d travel_db
```

#### Via Application Properties
```properties
# Assistant DB (with pgvector)
spring.datasource.url=jdbc:postgresql://localhost:5432/assistant_db
spring.datasource.username=postgres
spring.datasource.password=postgres

# BackOffice DB
spring.datasource.url=jdbc:postgresql://localhost:5432/backoffice_db
spring.datasource.username=postgres
spring.datasource.password=postgres

# Travel DB
spring.datasource.url=jdbc:postgresql://localhost:5432/travel_db
spring.datasource.username=postgres
spring.datasource.password=postgres
```

## Files

- `docker-compose.yml` - Docker Compose configuration
- `init-databases.sql` - Database initialization script
- `pgadmin-servers.json` - pgAdmin server configuration
- `start-postgres.sh` - Startup script
- `README.md` - This documentation
