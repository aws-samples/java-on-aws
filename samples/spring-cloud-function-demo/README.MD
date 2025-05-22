# Spring Cloud Function AWS Demo

This project demonstrates how to use Spring Cloud Function with AWS Lambda, showcasing function routing, and deployment to AWS Lambda using AWS SAM.

## Overview

Spring Cloud Function is a framework that promotes the implementation of business logic via functions. It abstracts away the underlying runtime platform, allowing the same code to run as a web endpoint, a stream processor, or a task. This project demonstrates:

- Function definition and routing
- Custom message routing
- Deployment to AWS Lambda
- Integration with AWS services (API Gateway, SQS)

## Project Structure

- `SpringCloudFunctionDemo.java`: Main application class with function definitions
- `Unicorn.java`: Simple data model class
- `template.yaml`: AWS SAM template for deployment
- `TestHttp.http`: HTTP request examples for local testing

## Functions Implemented

This demo includes several function implementations:

- `lowerCase`: Converts input string to lowercase
- `upperCase`: Converts input string to uppercase
- `reverse`: Reverses the input string
- `helloUnicorn`: Processes a Unicorn object and returns a greeting
- `asyncProcessor`: Consumes SQS events and logs the number of messages processed
- `noOpFunction`: Default function when no proper routing is found

## Custom Routing

The application demonstrates custom routing using `MessageRoutingCallback`. The router inspects the `x-routing-key` header and routes to the appropriate function:

- `uppercase` → `upperCase` function
- `lowercase` → `lowerCase` function
- `reverse` → `reverse` function
- `unicorn` → `helloUnicorn` function

## Local Development

### Prerequisites

- Java 21
- Maven
- AWS SAM CLI (for deployment)

### Building the Application

```bash
mvn clean package
```

### Running Locally

```bash
mvn spring-boot:run
```

Once running, you can test the functions using the provided `TestHttp.http` file or with curl:

```bash
# Test lowercase function
curl -X POST http://localhost:8080/lowerCase -H "Content-Type: text/plain" -d "HELLO WORLD"

# Test uppercase function
curl -X POST http://localhost:8080/upperCase -H "Content-Type: text/plain" -d "hello world"

# Test custom routing
curl -X POST http://localhost:8080/functionRouter -H "Content-Type: text/plain" -H "x-routing-key: uppercase" -d "hello world"
```

## AWS Deployment

This project uses AWS SAM for deployment to AWS Lambda.

### Prerequisites

- AWS CLI configured with appropriate credentials
- AWS SAM CLI installed

### Deployment Steps

1. Build the application:
   ```bash
   mvn clean package
   ```

2. Deploy using SAM:
   ```bash
   sam deploy --guided
   ```

3. Follow the prompts to complete the deployment.

### AWS Resources Created

The SAM template creates the following resources:

- **API Gateway**: Exposes the Spring Cloud Function as a REST API
- **Lambda Functions**:
  - `SpringCloudFunction`: Handles API requests
  - `MessageProcessor`: Processes SQS messages
- **SQS Queue**: For asynchronous message processing

## Testing in AWS

After deployment, you can test the API using the endpoint URL provided in the outputs:

```bash
# Test the deployed API
curl -X POST https://{api-id}.execute-api.{region}.amazonaws.com/Prod/uppercase/ -H "Content-Type: text/plain" -d "hello world"
```

To test the SQS integration, send a message to the created queue:

```bash
aws sqs send-message --queue-url {QueueURL} --message-body "Test message"
```

## Function Composition

Spring Cloud Function supports function composition. For example:

```bash
# Apply reverse then uppercase
curl -X POST http://localhost:8080/reverse,upperCase -H "Content-Type: text/plain" -d "hello world"
```

This will first reverse "hello world" to "dlrow olleh" and then convert it to uppercase: "DLROW OLLEH".

## Additional Resources

- [Spring Cloud Function Documentation](https://spring.io/projects/spring-cloud-function)
- [AWS Lambda Java Runtime](https://docs.aws.amazon.com/lambda/latest/dg/lambda-java.html)
- [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
