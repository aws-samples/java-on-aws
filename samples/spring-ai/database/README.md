# Spring AI Database Infrastructure

This project provides a comprehensive database infrastructure for Spring AI applications, featuring PostgreSQL with pgvector extension for vector embeddings storage and retrieval. The setup includes multiple databases for different application components and a pre-configured pgAdmin interface for easy database management.

## Stack Overview

- **PostgreSQL 16** with pgvector extension for vector similarity search
- **pgAdmin 4 (v9.5)** for database administration via web interface
- **Docker Compose** for containerized deployment
- **Pre-initialized databases** for various application domains

## Purpose

This database infrastructure serves as the foundation for Spring AI applications that require:

1. Vector storage and similarity search capabilities (via pgvector)
2. Structured data storage for business applications
3. Sample data for demonstration and testing purposes

The setup is designed to support a microservices architecture with separate databases for different application domains while providing a unified management interface.

## Quick Start

### Starting the Database Environment

```bash
cd samples/spring-ai/database/
./start-postgres.sh
```

This script will:
- Start PostgreSQL with pgvector extension
- Initialize all databases and load sample data
- Start pgAdmin web interface
- Display connection information

### Stopping the Database Environment

Either:
- Press `Ctrl+C` in the terminal where the start script is running
- Or run: `docker-compose down --volumes`

## Architecture

### Database Structure

The setup creates three separate databases within a single PostgreSQL instance:

1. **assistant_db**
   - Primary database for AI assistant functionality
   - Includes pgvector extension for embedding storage and similarity search
   - Optimized for vector operations

2. **backoffice_db**
   - Administrative and management functionality
   - Standard PostgreSQL database without specialized extensions

3. **travel_db**
   - Sample travel domain data
   - Contains structured data for various travel entities
   - Used for demonstration and testing purposes

### Container Architecture

The infrastructure consists of two Docker containers:

1. **PostgreSQL Container (pgvector/pgvector:pg16)**
   - Runs PostgreSQL 16 with pgvector extension
   - Exposes port 5432 for database connections
   - Mounts initialization scripts for database setup
   - Persists data via Docker volume

2. **pgAdmin Container (dpage/pgadmin4:9.5)**
   - Provides web-based database administration
   - Pre-configured with connection to PostgreSQL
   - Exposes port 8090 for web access
   - Persists configuration via Docker volume

## Connection Details

### PostgreSQL

- **Host**: localhost
- **Port**: 5432
- **Username**: postgres
- **Password**: postgres
- **Databases**: assistant_db, backoffice_db, travel_db

### pgAdmin

- **URL**: http://localhost:8090
- **Email**: admin@admin.com
- **Password**: admin
- **Pre-configured Servers**: All databases are automatically configured

## Application Integration

### Spring Boot Configuration

Add the following to your `application.properties` or `application.yml` file:

```properties
# For assistant_db with pgvector
spring.datasource.url=jdbc:postgresql://localhost:5432/assistant_db
spring.datasource.username=postgres
spring.datasource.password=postgres

# For backoffice_db
spring.datasource.url=jdbc:postgresql://localhost:5432/backoffice_db
spring.datasource.username=postgres
spring.datasource.password=postgres

# For travel_db
spring.datasource.url=jdbc:postgresql://localhost:5432/travel_db
spring.datasource.username=postgres
spring.datasource.password=postgres
```

## Best Practices

### Security Considerations

- **Production Deployment**: Change default credentials before deploying to production
- **Network Security**: Restrict database access using network policies
- **Encryption**: Enable SSL for database connections in production
- **Backup Strategy**: Implement regular database backups

### Performance Optimization

- **pgvector Indexing**: Create appropriate indexes for vector columns
- **Connection Pooling**: Use connection pooling in your application
- **Query Optimization**: Monitor and optimize slow queries
- **Resource Allocation**: Adjust container resources based on workload

### Development Workflow

- **Database Migrations**: Use tools like Flyway or Liquibase for schema evolution
- **Version Control**: Keep database scripts in version control
- **Testing**: Create separate test databases with minimal test data
- **Local Development**: Use this setup for local development only

## Project Files

- `docker-compose.yml` - Container configuration
- `init-databases.sql` - Creates the three databases and enables pgvector
- `init-travel-hotels.sql` - Initializes hotel data in travel_db
- `init-travel-flights.sql` - Initializes flight and airport data in travel_db
- `pgadmin-servers.json` - Pre-configures pgAdmin connections
- `start-postgres.sh` - Convenience script to start the environment
- `.gitignore` - Prevents committing temporary files

## Troubleshooting

### Common Issues

1. **Port Conflicts**: If port 5432 or 8090 is already in use, modify the port mappings in `docker-compose.yml`
2. **Container Startup Failures**: Check Docker logs with `docker-compose logs`
3. **Data Persistence Issues**: Ensure Docker volumes are properly configured
4. **pgAdmin Connection Problems**: Verify network settings and container health

### Resetting the Environment

To completely reset the environment and start fresh:

```bash
docker-compose down --volumes --remove-orphans
docker-compose up
```

## Future Enhancements

- Add support for additional PostgreSQL extensions
- Implement automated backup and restore functionality
- Add more sample datasets for different domains
- Create Kubernetes deployment configuration
