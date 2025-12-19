# Java on AWS Immersion Day

![Java on AWS](resources/welcome.png)

This project contains the supporting code for the Java on AWS Immersion Day. You can find the instructions for the hands-on lab [here](https://catalog.workshops.aws/java-on-aws).

# Overview
In this workshop you will learn how to build cloud-native Java applications, best practices and performance optimizations techniques. You will also learn how to migrate your existing Java application to container services such as AWS AppRunner, Amazon ECS and Amazon EKS or how to to run them as Serverless AWS Lambda functions.

## Updated for Java 25 and Spring Boot 4
This workshop has been updated to use the latest versions:
- **Java 25** - The latest LTS release with enhanced performance and new language features
- **Spring Boot 4.0** - The latest major release with improved native compilation and enhanced observability

### Key Benefits of the Upgrade:
- **Performance**: Java 25 includes significant JVM improvements and optimizations
- **Native Compilation**: Enhanced GraalVM support for faster startup times
- **Modern Language Features**: Access to the latest Java language enhancements
- **Spring Boot 4**: Improved developer experience and production-ready features

### Prerequisites:
- Java 25 JDK installed
- Maven 3.9+ 
- Docker (for integration tests)

# Modules and paths
The workshop is structured in multiple independent modules that can be chosen in any kind of order - with a few exceptions that mention a prerequisite of another module. While you can feel free to chose the path to your own preferences, we prepared three example paths through this workshop based on your experience:

![Java on AWS](resources/paths.png)

## Applications Status
All applications have been successfully updated and tested:

### ✅ unicorn-store-spring
- **Status**: Updated to Java 25 & Spring Boot 4.0
- **Compilation**: ✅ Success
- **Notes**: Main application with full Spring Boot features

### ✅ unicorn-spring-ai-agent  
- **Status**: Updated to Java 25 & Spring Boot 4.0
- **Compilation**: ✅ Success
- **Notes**: AI agent with Spring AI integration

### ✅ jvm-analysis-service
- **Status**: Updated to Java 25 & Spring Boot 4.0
- **Compilation**: ✅ Success
- **Notes**: JVM performance analysis service

### ✅ Integration Tests
- **Status**: Updated to use Testcontainers with Docker
- **Notes**: Tests use PostgreSQL and LocalStack containers for realistic testing
- **Requirements**: Docker Desktop must be running
- **Test Results**: All 9 tests pass with full database and AWS service integration

## Quick Start
```bash
# Compile all applications
cd apps/unicorn-store-spring && mvn clean compile
cd ../unicorn-spring-ai-agent && mvn clean compile  
cd ../jvm-analysis-service && mvn clean compile

# Run tests (requires Docker)
mvn clean test
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
