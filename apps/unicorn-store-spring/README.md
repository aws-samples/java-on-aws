# Unicorn Store: A Spring Boot REST API for Managing Unicorns

The Unicorn Store is a robust Spring Boot application that provides a RESTful API for managing unicorns. It offers CRUD operations for unicorn entities, integrates with AWS services, and uses PostgreSQL for data persistence.

## Project Description

The Unicorn Store is designed to showcase best practices in building a modern, cloud-native Spring Boot application. It leverages several key technologies and patterns:

- **Spring Boot**: Provides the core framework for building the application, including dependency injection, web services, and data access.
- **PostgreSQL**: Used as the primary database for storing unicorn information.
- **AWS SDK**: Integrates with various AWS services, including EventBridge for event publishing, S3 for object storage, and DynamoDB for NoSQL data storage.
- **Docker**: The application can be containerized for easy deployment and scaling.
- **Testcontainers**: Enables integration testing with a real PostgreSQL database running in a container.

Key features of the Unicorn Store include:

- RESTful API for creating, reading, updating, and deleting unicorn entities
- Event publishing to AWS EventBridge for each unicorn operation
- Comprehensive integration tests using RestAssured and Testcontainers
- Support for native compilation using GraalVM
- Configurable deployment options, including Docker and Cloud Native Buildpacks

The application demonstrates how to build a scalable, cloud-ready microservice that can be easily deployed and integrated into a larger ecosystem of services.

## Infrastructure

The Unicorn Store application uses the following key infrastructure components:

1. PostgreSQL Container (for testing):
   - Type: PostgreSQLContainer
   - Image: postgres:16.4
   - Database Name: unicorns
   - Username: postgres
   - Password: postgres

This container is defined in the `ContainersConfig` class and is used for integration testing. It ensures that tests run against a real PostgreSQL instance, improving the reliability of the test suite.

Note: In a production environment, you would typically use a managed PostgreSQL service or a dedicated PostgreSQL server instead of a container.