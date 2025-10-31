## Preparation

> In the terminal:

```bash
mkdir spring-ai-agent
code spring-ai-agent/
```

In the new terminal (Main terminal):

```bash
# git clone https://github.com/aws-samples/java-on-aws.git ./java-on-aws
# export SOURCES_FOLDER=$(pwd)/java-on-aws/samples/spring-ai-te-agent

export SOURCES_FOLDER=/Users/bezsonov/sources/workshops/java-on-aws/samples/spring-ai-te-agent
export AWS_REGION=us-east-1
```

> **AWS Credentials Setup:**
>
> Add AWS credentials to the main terminal using one of these methods:
> 1. **AWS CLI**: `aws configure` (recommended)
> 2. **Environment variables**:
>    ```bash
>    export AWS_ACCESS_KEY_ID=your-access-key-id
>    export AWS_SECRET_ACCESS_KEY=your-secret-access-key
>    ```
> 3. **Create .env file** in the project root with your credentials

## 01. Create Spring AI App

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/01-create-app.sh
```

## Run the AI Agent

Open the new terminal (AI Agent terminal):

```bash
cd ai-agent
export AWS_REGION=us-east-1
```

> Ensure AWS credentials are available in this terminal (inherit from main terminal or set again)

In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> Who are you?

> What is our company name?

## 02. Add Memory

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/02-add-memory.sh
```

Open the new terminal (Database terminal):

```bash
cd database/
./start-postgres.sh
```

> In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> Our company name is Company1

> What is our company name?

> What is our travel and expenses policy?

## 03. Add RAG

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/03-add-rag.sh
```

> In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

> In the main terminal:

```bash
# code $SOURCES_FOLDER/ai-agent/samples/travel_and_expenses_policy.md
curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @$SOURCES_FOLDER//ai-agent/samples/travel_and_expenses_policy.md \
  http://localhost:8080/api/rag-load

```

```
cd /Users/bezsonov/sources/workshops/java-on-aws/samples/spring-ai-te-agent/ai-agent && curl -X POST -H "Content-Type: text/plain" --data-binary @./samples/travel_and_expenses_policy.md http://localhost:8080/api/rag-load
```

Open localhost:8080 in the browser and ask questions:

> What is our travel and expenses policy?

> What is the date today?

## 04. Add Tools

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/04-add-tools.sh
```

> In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> What is the date today?

> What is the weather in Paris next Monday?

## 05. Add MCP

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/05-add-mcp.sh
```

**Microservice Architecture:**
- **Weather Service** (port 8081): Weather forecasts and climate data
- **Travel Service** (port 8082): Hotel and flight booking
- **Backoffice Service** (port 8083): Expense management and currency conversion
- **AI Agent** (port 8080): Central AI assistant orchestrating all services

**Start the microservices in the following order:**

Open the new terminal (Weather terminal - port 8081):

```bash
cd weather/
./mvnw spring-boot:run
```

Open the new terminal (Travel terminal - port 8082):

```bash
cd travel/
./mvnw spring-boot:test-run
```

Open the new terminal (Backoffice terminal - port 8083):

```bash
cd backoffice/
./mvnw spring-boot:test-run
```

> **Note**: Travel and Backoffice services use `test-run` which automatically starts PostgreSQL containers with Testcontainers - no manual database setup required!

> In the AI Agent terminal (port 8080):

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> What's the weather in London today?

> My name is John Doe. Please find me inbound and outbound flights and accommodations for a trip from London to Paris next week, From Monday to Friday. I travel alone, prefer BA flights in the first part of the day, and choose accommodation which is the most expensive, but comply with our travel policy.
Give me a travel itinerary with flights, accommodation, prices and weather forecast for each day of the travel.

## 06. Add Multi-model, Multi-modal

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/06-add-multi.sh
```